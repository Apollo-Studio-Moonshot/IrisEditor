import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// How the editor surface and the Markdown preview share the window.
enum EditorViewMode: Equatable {
    case source
    case split
    case preview

    /// Cycles source → split → preview → source.
    var next: EditorViewMode {
        switch self {
        case .source: return .split
        case .split: return .preview
        case .preview: return .source
        }
    }

    var toolbarIcon: String {
        switch self {
        case .source: return "doc.richtext"
        case .split: return "rectangle.split.2x1"
        case .preview: return "text.alignleft"
        }
    }

    var toolbarHelp: String {
        switch self {
        case .source: return "Split Editor + Preview (⌥⌘P)"
        case .split: return "Preview Only (⌥⌘P)"
        case .preview: return "Edit Markdown (⌥⌘P)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Open documents, one per editor tab.
    @Published private(set) var tabs: [EditorDocument] = []

    /// The editor window hosting the tab strip, adopted via `WindowConfigurator` so
    /// closing the last tab closes that window even when another window holds focus.
    weak var editorWindow: NSWindow?

    /// Index of the active tab in `tabs`.
    @Published private(set) var currentTabIndex = 0

    @Published private(set) var document = EditorDocument() {
        didSet {
            bindDocument()
            cursorLine = 1
            cursorColumn = 1
            findMatches = []
            findMatchIndex = -1
            clearFindHighlights()
        }
    }

    @Published var settings = EditorSettings.load()

    @Published private(set) var cursorLine = 1
    @Published private(set) var cursorColumn = 1

    @Published var showFindReplace = false {
        didSet {
            guard !isUpdatingPanels else { return }
            if showFindReplace {
                isUpdatingPanels = true
                showGoToLine = false
                isUpdatingPanels = false
                refreshFindHighlights()
            } else if !showGoToLine {
                clearFindHighlights()
            }
        }
    }

    @Published var showGoToLine = false {
        didSet {
            guard !isUpdatingPanels else { return }
            if showGoToLine {
                isUpdatingPanels = true
                showFindReplace = false
                isUpdatingPanels = false
                clearFindHighlights()
            } else if !showFindReplace {
                clearFindHighlights()
            }
        }
    }

    /// Whether the rendered Markdown preview replaces the editor source view.
    @Published var viewMode: EditorViewMode = .source

    /// Obsidian-style command palette overlay.
    @Published var showCommandPalette = false

    /// Obsidian-style document outline sidebar panel.
    @Published var showOutline = false

    /// Obsidian-style fuzzy quick switcher for open tabs and recent files.
    @Published var showQuickSwitcher = false

    /// Optional query used when the quick switcher is opened from a wiki link.
    @Published var quickSwitcherInitialQuery = ""

    /// Most-recently opened or saved files, newest first.
    @Published private(set) var recentFiles: [URL] = RecentFiles.load()

    /// File-backed tabs that were closed this session, newest last, used by Reopen Closed Tab.
    @Published private(set) var closedFileURLs: [URL] = []

    @Published var findText = "" {
        didSet {
            if findText != oldValue {
                findMatchIndex = -1
            }
        }
    }

    @Published var replaceText = ""

    /// Find options that change how matches are computed.
    @Published var findCaseSensitive = false {
        didSet { if findCaseSensitive != oldValue { recomputeFindMatches() } }
    }
    @Published var findWholeWord = false {
        didSet { if findWholeWord != oldValue { recomputeFindMatches() } }
    }

    @Published private(set) var findMatchIndex = -1
    @Published private(set) var findMatches: [NSRange] = []

    private var cancellables = Set<AnyCancellable>()
    private var documentObservation: AnyCancellable?
    private var isUpdatingPanels = false

    private init() {
        tabs = [document]
        observeChanges()
    }

    // MARK: - Document lifecycle

    func newDocument() {
        let fresh = EditorDocument()
        withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
            tabs.append(fresh)
            currentTabIndex = tabs.count - 1
            document = fresh
        }
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index), index != currentTabIndex else { return }
        withAnimation(.snappy(duration: 0.24)) {
            currentTabIndex = index
            document = tabs[index]
        }
    }

    /// Selects a tab by its 1-based position for `⌘1`…`⌘9`. `9` selects the last tab,
    /// matching Safari, Finder, and most browsers.
    func selectTab(number: Int) {
        guard (1...9).contains(number), !tabs.isEmpty else { return }
        selectTab(at: number == 9 ? tabs.count - 1 : number - 1)
    }

    /// Closes a tab. Prompts to save or discard when its document is dirty; closing the
    /// last tab closes the window itself instead of trapping the user behind a rebuilt
    /// empty tab.
    ///
    /// Closing a background tab keeps the current document in front instead of jumping
    /// to a neighbor, matching native tab behavior.
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let target = tabs[index]
        let activeDocument = document
        let wasActive = target.id == activeDocument.id

        if target.isDirty {
            guard confirmDiscardChanges(for: target) else { return }
        }

        guard let removalIndex = tabs.firstIndex(where: { $0.id == target.id }) else { return }
        let closedURL = target.fileURL

        if tabs.count == 1 {
            withAnimation(.snappy(duration: 0.22)) {
                _ = tabs.remove(at: removalIndex)
            }
            EditorViewportStore.remove(documentID: target.id)
            (editorWindow ?? NSApp.keyWindow)?.close()
            return
        }

        withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
            tabs.remove(at: removalIndex)
            EditorViewportStore.remove(documentID: target.id)

            if let closedURL {
                closedFileURLs.append(closedURL)
                if closedFileURLs.count > 20 {
                    closedFileURLs.removeFirst(closedFileURLs.count - 20)
                }
            }

            if wasActive {
                let next = min(index, tabs.count - 1)
                currentTabIndex = next
                document = tabs[next]
            } else if let activeIndex = tabs.firstIndex(where: { $0.id == activeDocument.id }) {
                currentTabIndex = activeIndex
                // Reassigning the same document would reset the caret and find state.
                if document.id != activeDocument.id {
                    document = activeDocument
                }
            } else {
                let next = min(removalIndex, tabs.count - 1)
                currentTabIndex = next
                document = tabs[next]
            }
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownFileType.editable
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose Markdown or plain-text files to open."

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        open(urls: panel.urls)
    }

    func open(urls: [URL]) {
        for url in urls {
            open(url: url)
        }
    }

    /// Reopens the most recently closed file-backed tab.
    func reopenClosedTab() {
        while let url = closedFileURLs.popLast() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            open(url: url)
            return
        }
    }

    /// Opens a file in a new tab, or focuses the existing tab when it is already open.
    func open(url: URL) {
        let standardized = url.standardizedFileURL

        // If the file is already open in a tab, just focus that tab.
        if let existing = tabs.firstIndex(where: { $0.fileURL?.standardizedFileURL == standardized }) {
            selectTab(at: existing)
            return
        }

        do {
            var encoding: String.Encoding = .utf8
            let contents = try String(contentsOf: standardized, usedEncoding: &encoding)

            let opened = EditorDocument()
            opened.text = contents
            opened.fileURL = standardized
            opened.isDirty = false
            recordRecent(standardized)

            withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
                tabs.append(opened)
                currentTabIndex = tabs.count - 1
                document = opened
            }
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentError("Couldn’t open “\(url.lastPathComponent)”.", error: error)
        }
    }

    /// Resolves an Obsidian-style `[[wiki link]]`, focusing open tabs, recent files, or
    /// notes next to the current document. Missing notes are created lazily, matching
    /// Obsidian's behavior for unresolved links.
    func openWikiLink(_ rawTarget: String) {
        let trimmed = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let pieces = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawNote = pieces.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let heading = pieces.count > 1
            ? String(pieces[1]).trimmingCharacters(in: .whitespaces)
            : nil

        let noteName: String
        if rawNote.isEmpty {
            noteName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        } else {
            noteName = rawNote
        }

        let baseName: String
        let lastComponent = (noteName as NSString).lastPathComponent
        let extensionName = (lastComponent as NSString).pathExtension.lowercased()
        if ["md", "markdown"].contains(extensionName) {
            baseName = (lastComponent as NSString).deletingPathExtension
        } else {
            baseName = lastComponent
        }

        if let index = tabs.firstIndex(where: { tab in
            let openName = tab.fileURL?.deletingPathExtension().lastPathComponent
                ?? (tab.displayName as NSString).deletingPathExtension
            return openName.caseInsensitiveCompare(baseName) == .orderedSame
        }) {
            selectTab(at: index)
            revealHeading(named: heading)
            return
        }

        if let recent = recentFiles.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
                && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(baseName) == .orderedSame
        }) {
            open(url: recent)
            revealHeading(named: heading)
            return
        }

        guard let folder = document.fileURL?.deletingLastPathComponent() else {
            presentQuickSwitcher(for: noteName)
            return
        }

        let hasMarkdownExtension = ["md", "markdown"].contains(
            (noteName as NSString).pathExtension.lowercased()
        )
        let fileName = hasMarkdownExtension
            ? noteName
            : noteName + "." + MarkdownFileType.defaultExtension
        guard !fileName.contains(".."), !fileName.hasPrefix("/") else {
            presentQuickSwitcher(for: baseName)
            return
        }

        let candidate = folder.appendingPathComponent(fileName).standardizedFileURL
        let folderPath = folder.standardizedFileURL.path
        guard candidate.path.hasPrefix(folderPath + "/") else {
            presentQuickSwitcher(for: baseName)
            return
        }

        if FileManager.default.fileExists(atPath: candidate.path) {
            open(url: candidate)
            revealHeading(named: heading)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: candidate.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let title = candidate.deletingPathExtension().lastPathComponent
            try "# \(title)\n".write(to: candidate, atomically: true, encoding: .utf8)
            open(url: candidate)
            revealHeading(named: heading)
        } catch {
            presentError("Couldn’t create “\(candidate.lastPathComponent)”.", error: error)
        }
    }

    private func revealHeading(named name: String?) {
        guard let name, !name.isEmpty else { return }
        guard let heading = MarkdownOutline.headings(in: document.text).first(where: {
            $0.title.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            return
        }
        reveal(line: heading.line)
    }

    private func presentQuickSwitcher(for query: String) {
        quickSwitcherInitialQuery = query
        withAnimation(.snappy(duration: 0.2)) {
            showCommandPalette = false
            showQuickSwitcher = true
        }
    }

    @discardableResult
    func saveDocument() -> Bool {
        saveChanges(for: document)
    }

    @discardableResult
    func saveDocumentAs() -> Bool {
        saveDocumentAs(for: document)
    }

    /// Saves a specific document, asking for a location when it has no file URL yet.
    /// Targeting the document directly keeps background-tab saves from stealing focus.
    @discardableResult
    private func saveChanges(for target: EditorDocument) -> Bool {
        guard let url = target.fileURL else {
            return saveDocumentAs(for: target)
        }
        return save(target, to: url)
    }

    @discardableResult
    private func saveDocumentAs(for target: EditorDocument) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = MarkdownFileType.editable
        panel.nameFieldStringValue = target.displayName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(target, to: url)
    }

    /// Exports the current document as a self-contained HTML file. The Markdown source
    /// and its dirty state are left untouched, so export never affects autosave.
    func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        let baseName = (document.displayName as NSString).deletingPathExtension
        let title = baseName.isEmpty ? "Untitled" : baseName
        panel.nameFieldStringValue = title + ".html"
        panel.message = "Export the rendered document as a standalone HTML file."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = MarkdownHTMLExport.document(from: document.text, title: title)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentError("Couldn't export “\(url.lastPathComponent)”.", error: error)
        }
    }

    @discardableResult
    private func save(to url: URL) -> Bool {
        save(document, to: url)
    }

    @discardableResult
    private func save(_ target: EditorDocument, to url: URL) -> Bool {
        // If the user chose a Markdown panel without an extension, default to `.md`.
        let resolved: URL
        if url.pathExtension.isEmpty, let withExtension = url.appendingPathExtension(MarkdownFileType.defaultExtension) as URL? {
            resolved = withExtension
        } else {
            resolved = url
        }

        do {
            try target.text.write(to: resolved, atomically: true, encoding: .utf8)
            target.fileURL = resolved
            target.isDirty = false
            recordRecent(resolved)
            return true
        } catch {
            presentError("Couldn't save \"\(resolved.lastPathComponent)\".", error: error)
            return false
        }
    }

    private func recordRecent(_ url: URL) {
        let updated = RecentFiles.recording(url, in: recentFiles)
        guard updated != recentFiles else { return }
        recentFiles = updated
        RecentFiles.save(updated)
    }

    func clearRecentFiles() {
        recentFiles = []
        RecentFiles.save([])
    }

    /// Offers to save unsaved changes before a destructive action (new, open, quit).
    func confirmDiscardChanges() -> Bool {
        confirmDiscardChanges(for: document)
    }

    /// Offers to save, discard, or cancel the unsaved changes of a specific document.
    /// Returns `false` only when the user cancels.
    func confirmDiscardChanges(for target: EditorDocument) -> Bool {
        guard target.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save the changes made to “\(target.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveChanges(for: target)
        case .alertSecondButtonReturn:
            target.isDirty = false
            return true
        default:
            return false
        }
    }

    /// Prompts for every dirty tab in order (used before quitting); false on cancel.
    func confirmDiscardAllTabs() -> Bool {
        for tab in tabs where tab.isDirty {
            guard confirmDiscardChanges(for: tab) else { return false }
        }
        return true
    }

    // MARK: - Find, replace, and go to line

    func performFind(forward: Bool) {
        guard !findMatches.isEmpty else { return }

        if findMatchIndex < 0 {
            findMatchIndex = forward ? 0 : findMatches.count - 1
        } else if forward {
            findMatchIndex = (findMatchIndex + 1) % findMatches.count
        } else {
            findMatchIndex = (findMatchIndex - 1 + findMatches.count) % findMatches.count
        }

        postFindHighlight(scroll: true)
    }

    func replaceCurrentMatch() {
        guard findMatchIndex >= 0, findMatchIndex < findMatches.count else { return }
        let range = findMatches[findMatchIndex]
        postReplacement(ranges: [range])
        findMatchIndex = -1
    }

    func replaceAllMatches() {
        guard !findMatches.isEmpty else { return }
        postReplacement(ranges: findMatches)
        findMatchIndex = -1
    }

    func goToLine(_ line: Int) {
        guard line > 0 else { return }
        NotificationCenter.default.post(name: .goToLine, object: nil, userInfo: ["line": line])
        closeFindPanel()
    }

    /// Jumps to a line from the outline or quick switcher, leaving preview-only mode so
    /// the caret is actually visible.
    func reveal(line: Int) {
        let post = {
            NotificationCenter.default.post(name: .goToLine, object: nil, userInfo: ["line": line])
        }

        guard viewMode == .preview else {
            post()
            return
        }

        // Wait for the AppKit editor to be rebuilt before delivering the jump.
        withAnimation(.snappy(duration: 0.22)) {
            viewMode = .source
        } completion: {
            post()
        }
    }

    func closeFindPanel() {
        showFindReplace = false
        showGoToLine = false
        clearFindHighlights()
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    func refreshFindHighlights() {
        guard showFindReplace else { return }
        postFindHighlight(scroll: false)
    }

    func clearFindHighlights() {
        NotificationCenter.default.post(
            name: .findHighlight,
            object: nil,
            userInfo: ["ranges": [NSRange]()]
        )
    }

    private func postReplacement(ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }
        NotificationCenter.default.post(
            name: .replaceMatches,
            object: nil,
            userInfo: [
                "ranges": ranges,
                "replacement": replaceText
            ]
        )
        // The ranges are stale as soon as the text changes. Drop them immediately so a
        // second Replace/Replace All cannot mutate the wrong offsets before the debounced
        // recompute catches up.
        findMatches = []
        findMatchIndex = -1
        clearFindHighlights()
    }

    private func postFindHighlight(scroll: Bool) {
        var userInfo: [String: Any] = ["ranges": findMatches]
        if findMatchIndex >= 0, findMatchIndex < findMatches.count {
            userInfo["current"] = findMatches[findMatchIndex]
            userInfo["scroll"] = scroll
        }
        NotificationCenter.default.post(name: .findHighlight, object: nil, userInfo: userInfo)
    }

    // MARK: - Command palette & outline

    func toggleCommandPalette() {
        withAnimation(.snappy(duration: 0.2)) {
            showCommandPalette.toggle()
            if showCommandPalette {
                showQuickSwitcher = false
            }
        }
        if !showCommandPalette {
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    func dismissCommandPalette() {
        guard showCommandPalette else { return }
        withAnimation(.snappy(duration: 0.18)) {
            showCommandPalette = false
        }
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    func toggleQuickSwitcher() {
        let opening = !showQuickSwitcher
        withAnimation(.snappy(duration: 0.2)) {
            showQuickSwitcher.toggle()
            if showQuickSwitcher {
                showCommandPalette = false
            }
        }
        if opening {
            quickSwitcherInitialQuery = ""
        } else {
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    func dismissQuickSwitcher() {
        guard showQuickSwitcher else { return }
        withAnimation(.snappy(duration: 0.18)) {
            showQuickSwitcher = false
        }
        quickSwitcherInitialQuery = ""
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    func consumeQuickSwitcherInitialQuery() -> String {
        let query = quickSwitcherInitialQuery
        quickSwitcherInitialQuery = ""
        return query
    }

    func toggleOutline() {
        withAnimation(.snappy(duration: 0.25)) {
            showOutline.toggle()
        }
    }

    // MARK: - View commands

    func zoomIn() {
        settings.fontSize = min(32, settings.fontSize + 1)
    }

    func zoomOut() {
        settings.fontSize = max(8, settings.fontSize - 1)
    }

    func resetZoom() {
        settings.fontSize = EditorSettings.defaultFontSize
    }

    // MARK: - Markdown formatting

    /// Wraps the editor's selection with `prefix`/`suffix` (e.g. `**` for bold).
    /// If text is already wrapped, toggles the markers off.
    func toggleMarkdownFormat(prefix: String, suffix: String? = nil) {
        let suffix = suffix ?? prefix
        NotificationCenter.default.post(
            name: .toggleMarkdownFormat,
            object: nil,
            userInfo: ["prefix": prefix, "suffix": suffix]
        )
    }

    /// Inserts a Markdown snippet (e.g. a table template) at the current cursor position.
    func insertSnippet(_ text: String) {
        NotificationCenter.default.post(
            name: .insertSnippet,
            object: nil,
            userInfo: ["text": text]
        )
    }

    // MARK: - Observation

    private func bindDocument() {
        documentObservation = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func observeChanges() {
        $settings
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { settings in
                settings.save()
            }
            .store(in: &cancellables)

        let textChanges = $document.flatMap { document in
            document.$text.map { text in
                (id: document.id, text: text)
            }
        }

        Publishers.CombineLatest($findText, textChanges)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] query, change in
                self?.updateFindMatches(query: query, text: change.text)
            }
            .store(in: &cancellables)

        // Auto-save: when the user stops typing for 2 seconds, save to disk if the
        // document has a file URL and is dirty. Mirrors Obsidian's seamless save behavior.
        // Subscribing through `textChanges` means tab switches follow the active document
        // instead of leaving the subscription pinned to the first one.
        textChanges
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                guard change.id == self.document.id,
                      self.document.isDirty,
                      let url = self.document.fileURL else {
                    return
                }
                _ = self.save(to: url)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .cursorDidChange)
            .compactMap { note -> (line: Int, column: Int)? in
                guard let line = note.userInfo?["line"] as? Int,
                      let column = note.userInfo?["column"] as? Int else {
                    return nil
                }
                return (line, column)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] position in
                self?.cursorLine = position.line
                self?.cursorColumn = position.column
            }
            .store(in: &cancellables)
    }

    private func updateFindMatches(query: String, text: String) {
        let matches = TextSearch.nsRanges(
            of: query,
            in: text,
            caseSensitive: findCaseSensitive,
            wholeWord: findWholeWord
        )
        findMatches = matches

        if matches.isEmpty {
            findMatchIndex = -1
        } else if findMatchIndex >= matches.count {
            findMatchIndex = matches.count - 1
        }

        // The find bar owns the highlight layer while it is visible; when it is closed
        // (or the go-to-line bar is showing instead), typing must not repaint stale matches.
        guard showFindReplace else { return }
        postFindHighlight(scroll: false)
    }

    private func recomputeFindMatches() {
        findMatchIndex = -1
        updateFindMatches(query: findText, text: document.text)
    }

    private func presentError(_ title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension Notification.Name {
    static let goToLine = Notification.Name("IrisEditor.goToLine")
    static let findHighlight = Notification.Name("IrisEditor.findHighlight")
    static let replaceMatches = Notification.Name("IrisEditor.replaceMatches")
    static let cursorDidChange = Notification.Name("IrisEditor.cursorDidChange")
    static let focusEditor = Notification.Name("IrisEditor.focusEditor")
    static let toggleMarkdownFormat = Notification.Name("IrisEditor.toggleMarkdownFormat")
    static let insertSnippet = Notification.Name("IrisEditor.insertSnippet")
    static let requestText = Notification.Name("IrisEditor.requestText")
}
