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
        case .source: return "Split Editor + Preview (⇧⌘P)"
        case .split: return "Preview Only (⇧⌘P)"
        case .preview: return "Edit Markdown (⇧⌘P)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Open documents, one per editor tab.
    @Published private(set) var tabs: [EditorDocument] = []

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
        tabs.append(fresh)
        currentTabIndex = tabs.count - 1
        document = fresh
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        currentTabIndex = index
        document = tabs[index]
    }

    /// Closes a tab. Prompts to save when its document is dirty; the last tab closes
    /// as a fresh untitled document so the window always has an editing surface.
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let target = tabs[index]

        if target.isDirty {
            guard saveTabChanges(for: target) else { return }
        }

        if let documentIndex = tabs.firstIndex(where: { $0.id == target.id }) {
            tabs.remove(at: documentIndex)
        }

        if tabs.isEmpty {
            newDocument()
            return
        }

        let next = min(index, tabs.count - 1)
        currentTabIndex = next
        document = tabs[next]
    }

    /// Saves dirty changes for a specific tab (used before closing), temporarily
    /// switching the active document so panel-driven saves target the right one.
    private func saveTabChanges(for target: EditorDocument) -> Bool {
        guard let targetIndex = tabs.firstIndex(where: { $0.id == target.id }) else { return true }
        let previousIndex = currentTabIndex

        if document.id != target.id {
            currentTabIndex = targetIndex
            document = target
        }

        let saved: Bool
        if let url = target.fileURL {
            saved = save(to: url)
        } else {
            saved = saveDocumentAs()
        }

        // Restore the originally active tab when the save was cancelled, so closing
        // a background tab never leaves the user staring at the wrong document.
        if !saved, tabs.indices.contains(previousIndex), document.id != tabs[previousIndex].id {
            currentTabIndex = previousIndex
            document = tabs[previousIndex]
        }
        return saved
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownFileType.editable
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose Markdown or plain-text files to open."

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        for url in panel.urls {
            open(url: url)
        }
    }

    private func open(url: URL) {
        // If the file is already open in a tab, just focus that tab.
        if let existing = tabs.firstIndex(where: { $0.fileURL == url }) {
            selectTab(at: existing)
            return
        }

        do {
            var encoding: String.Encoding = .utf8
            let contents = try String(contentsOf: url, usedEncoding: &encoding)

            let opened = EditorDocument()
            opened.text = contents
            opened.fileURL = url
            opened.isDirty = false
            tabs.append(opened)
            currentTabIndex = tabs.count - 1
            document = opened
        } catch {
            presentError("Couldn’t open “\(url.lastPathComponent)”.", error: error)
        }
    }

    @discardableResult
    func saveDocument() -> Bool {
        guard let url = document.fileURL else {
            return saveDocumentAs()
        }
        return save(to: url)
    }

    @discardableResult
    func saveDocumentAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = MarkdownFileType.editable
        panel.nameFieldStringValue = document.displayName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(to: url)
    }

    @discardableResult
    private func save(to url: URL) -> Bool {
        // If the user chose a Markdown panel without an extension, default to `.md`.
        let resolved: URL
        if url.pathExtension.isEmpty, let withExtension = url.appendingPathExtension(MarkdownFileType.defaultExtension) as URL? {
            resolved = withExtension
        } else {
            resolved = url
        }

        do {
            try document.text.write(to: resolved, atomically: true, encoding: .utf8)
            document.fileURL = resolved
            document.isDirty = false
            return true
        } catch {
            presentError("Couldn't save \"\(resolved.lastPathComponent)\".", error: error)
            return false
        }
    }

    /// Offers to save unsaved changes before a destructive action (new, open, quit).
    func confirmDiscardChanges() -> Bool {
        guard document.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save the changes made to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            _ = saveDocument()
            return !document.isDirty
        case .alertSecondButtonReturn:
            document.isDirty = false
            return true
        default:
            return false
        }
    }

    /// Prompts for every dirty tab in order (used before quitting); false on cancel.
    func confirmDiscardAllTabs() -> Bool {
        let previousIndex = currentTabIndex
        for (index, tab) in tabs.enumerated() where tab.isDirty {
            if document.id != tab.id {
                currentTabIndex = index
                document = tab
            }
            guard confirmDiscardChanges() else {
                if tabs.indices.contains(previousIndex) {
                    currentTabIndex = previousIndex
                    document = tabs[previousIndex]
                }
                return false
            }
        }
        if tabs.indices.contains(previousIndex), document.id != tabs[previousIndex].id {
            currentTabIndex = previousIndex
            document = tabs[previousIndex]
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
