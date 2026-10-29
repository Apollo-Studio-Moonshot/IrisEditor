import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// How the editor surface and the Markdown preview share the window.
enum EditorViewMode: String, Equatable {
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

    @Published var settings = EditorSettings.load() {
        didSet {
            if oldValue.aiConfiguration != settings.aiConfiguration {
                ai.apply(configuration: settings.aiConfiguration)
            }
            if oldValue.disabledPluginIDs != settings.disabledPluginIDs {
                reloadPlugins()
            }
            if oldValue.editingMode != settings.editingMode {
                editorModeLabel = nil
                NotificationCenter.default.post(name: .resetEditorMode, object: nil)
            }
        }
    }

    @Published private(set) var cursorLine = 1
    @Published private(set) var cursorColumn = 1

    /// Selection reported by the editor, used by plugins and commands.
    @Published private(set) var currentSelection = NSRange(location: 0, length: 0)

    /// Current Vim/Emacs mode badge, e.g. `VIM · NORMAL`; nil in Standard mode.
    @Published private(set) var editorModeLabel: String?

    /// The focused AppKit editor, adopted so plugin commands can apply undoable edits.
    weak var currentTextView: IrisTextView?

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

    /// Focus mode: hide chrome so only the document remains.
    @Published var isZenMode = false

    // MARK: - Vault

    /// Which pane the unified sidebar shows.
    @Published var sidebarTab: VaultPane = .files {
        didSet { if sidebarTab == .tags || sidebarTab == .backlinks || sidebarTab == .graph { refreshVaultIfNeeded() } }
    }

    /// Folder that acts as the note vault. Defaults to the current document's folder.
    @Published var vaultRootURL: URL?

    @Published private(set) var vaultFiles: [VaultFile] = []
    @Published private(set) var vaultTags: [VaultTag] = []
    @Published private(set) var vaultBacklinks: [VaultBacklink] = []
    @Published private(set) var vaultGraph = VaultGraph(nodes: [], edges: [])
    @Published private(set) var vaultTemplates: [URL] = []

    @Published var showVaultSearch = false
    @Published var vaultSearchQuery = ""
    @Published private(set) var vaultSearchResults: [VaultSearchResult] = []

    // MARK: - Wiki autocomplete

    @Published var showWikiSuggestions = false
    @Published var wikiSuggestionIndex = 0
    @Published private(set) var wikiSuggestions: [String] = []

    // MARK: - Documents

    /// Optional second document shown side-by-side.
    @Published var secondDocument: EditorDocument?

    /// Monotonic id used to discard stale asynchronous search results.
    private var vaultSearchGeneration = 0

    @Published var showVersionHistory = false
    @Published private(set) var versionHistory: [DocumentVersion] = []

    // MARK: - AI

    let ai = AIAssistant.shared
    @Published private(set) var isAIWorking = false
    @Published var aiStatusMessage: String?

    // MARK: - Plugins

    @Published private(set) var installedPlugins: [InstalledPlugin] = []
    @Published private(set) var pluginCommands: [PluginCommandDescriptor] = []
    @Published private(set) var pluginExporters: [PluginExporterDescriptor] = []
    @Published private(set) var pluginErrors: [String] = []

    private let pluginHost = PluginHost.shared

    private var vaultRefreshTask: Task<Void, Never>?
    private var vaultRefreshScheduled = false
    private var lastVaultRoot: URL?

    private static let vaultRootDefaultsKey = "IrisEditor.VaultRoot"

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
        ai.apply(configuration: settings.aiConfiguration)
        if let stored = UserDefaults.standard.string(forKey: Self.vaultRootDefaultsKey) {
            vaultRootURL = URL(fileURLWithPath: stored)
        }
        tabs = [document]
        restoreSession()
        observeChanges()
        reloadPlugins()
        refreshVault()
        if let root = effectiveVaultRoot {
            lastVaultRoot = root.standardizedFileURL
        }
    }

    // MARK: - Document lifecycle

    /// Vault used for the sidebar, search, tags, and backlinks.
    var effectiveVaultRoot: URL? {
        vaultRootURL ?? document.fileURL?.deletingLastPathComponent()
    }

    /// A "jump to line" that must be delivered once the target document is on screen.
    private var pendingReveal: (documentID: UUID, line: Int)?

    private func restoreSession() {
        var restoredTabs: [EditorDocument] = []
        var restoredSession: EditorSession?

        if let session = SessionStore.load() {
            restoredSession = session
            restoredTabs = session.openFiles.compactMap { path in
                let url = URL(fileURLWithPath: path)
                // Honour the file's own encoding instead of forcing UTF-8, otherwise a
                // UTF-16 or Latin-1 note silently fails to reopen.
                guard let contents = Self.readText(at: url) else { return nil }
                let reopened = EditorDocument()
                reopened.text = contents
                reopened.fileURL = url
                reopened.isDirty = false
                return reopened
            }
        }

        // Crash recovery: reopen untitled drafts saved before the app exited unexpectedly.
        // These are additive — a normal session restore must not hide them, which used to
        // make draft recovery unreachable and then lose the drafts for good.
        // Drop drafts nobody will ever reopen, so the recovery folder cannot grow forever.
        DraftStore.prune(olderThan: 14)
        let recovered = DraftStore.loadAll()
            .filter { !$0.text.isEmpty }
            .map { draft -> EditorDocument in
                let recoveredDocument = EditorDocument()
                recoveredDocument.text = draft.text
                recoveredDocument.draftID = draft.id
                recoveredDocument.isDirty = true
                return recoveredDocument
            }

        guard !restoredTabs.isEmpty || !recovered.isEmpty else { return }

        tabs = restoredTabs + recovered
        if let session = restoredSession, !restoredTabs.isEmpty {
            currentTabIndex = min(max(0, session.activeIndex), restoredTabs.count - 1)
            viewMode = EditorViewMode(rawValue: session.viewMode) ?? .source
            showOutline = session.sidebarVisible
            sidebarTab = VaultPane(rawValue: session.sidebarPane) ?? .files
            if let vaultRoot = session.vaultRoot {
                vaultRootURL = URL(fileURLWithPath: vaultRoot)
            }
        } else {
            currentTabIndex = 0
        }
        document = tabs[min(currentTabIndex, tabs.count - 1)]
    }

    /// Reads a file with its own encoding, falling back to UTF-8.
    static func readText(at url: URL) -> String? {
        var encoding: String.Encoding = .utf8
        guard let text = try? String(contentsOf: url, usedEncoding: &encoding) else {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return text
    }

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

        // Once the tab is gone the document is not coming back, so any crash-recovery
        // draft behind it must go too. This covers tabs that were saved (which already
        // clear their draft) as well as tabs closed without ever becoming dirty.
        if target.fileURL == nil {
            discardDraft(for: target)
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
            refreshVaultIfNeeded()
            refreshVersionHistory()
            saveSession()
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

        let html = MarkdownHTMLExport.document(
            from: document.text,
            title: title,
            using: settings.previewTheme
        )
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentError("Couldn't export “\(url.lastPathComponent)”.", error: error)
        }
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let baseName = (document.displayName as NSString).deletingPathExtension
        let title = baseName.isEmpty ? "Untitled" : baseName
        panel.nameFieldStringValue = title + ".pdf"
        panel.message = "Export the rendered document as a PDF."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = MarkdownHTMLExport.document(
            from: document.text,
            title: title,
            using: settings.previewTheme
        )

        Task { @MainActor in
            do {
                try await MarkdownPDFExporter.exportPDF(
                    html: html,
                    to: url,
                    baseURL: self.document.fileURL?.deletingLastPathComponent()
                )
            } catch {
                presentError("Couldn’t export the PDF.", error: error)
            }
        }
    }

    func exportRTF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rtf]
        panel.canCreateDirectories = true
        let baseName = (document.displayName as NSString).deletingPathExtension
        let title = baseName.isEmpty ? "Untitled" : baseName
        panel.nameFieldStringValue = title + ".rtf"
        panel.message = "Export the rendered document as rich text."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = MarkdownHTMLExport.document(
            from: document.text,
            title: title,
            using: settings.previewTheme
        )
        guard let data = MarkdownRTFExporter.data(html: html) else {
            presentInfo("Export failed", message: "The document could not be converted to RTF.")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            presentError("Couldn’t export the RTF.", error: error)
        }
    }

    func printDocument() {
        let title = document.displayName
        let html = MarkdownHTMLExport.document(
            from: document.text,
            title: title,
            using: settings.previewTheme
        )
        Task { @MainActor in
            do {
                try await MarkdownPDFExporter.printHTML(
                    html,
                    jobTitle: title,
                    baseURL: self.document.fileURL?.deletingLastPathComponent()
                )
            } catch {
                presentError("Couldn’t print the document.", error: error)
            }
        }
    }

    // MARK: - Plugins

    /// Rescans the plugins folder and publishes the commands/exporters it contributes.
    func reloadPlugins() {
        let result = pluginHost.loadPlugins(disabledIDs: Set(settings.disabledPluginIDs))
        installedPlugins = result.plugins
        pluginErrors = result.errors
        pluginCommands = result.plugins.filter(\.isEnabled).flatMap(\.commands)
        pluginExporters = result.plugins.filter(\.isEnabled).flatMap(\.exporters)
    }

    func openPluginsFolder() {
        let folder = pluginHost.pluginsDirectory
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func installSamplePlugin() {
        do {
            let folder = try pluginHost.installSamplePlugin()
            reloadPlugins()
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            presentError("Couldn’t install the sample plugin.", error: error)
        }
    }

    func setPluginEnabled(_ pluginID: String, enabled: Bool) {
        if enabled {
            settings.disabledPluginIDs.removeAll { $0 == pluginID }
        } else if !settings.disabledPluginIDs.contains(pluginID) {
            settings.disabledPluginIDs.append(pluginID)
        }
    }

    func runPluginCommand(_ command: PluginCommandDescriptor) {
        let selection = currentTextView?.selectedRange() ?? currentSelection
        let context = PluginCommandContext(
            text: document.text,
            selection: selection,
            documentName: document.displayName,
            filePath: document.fileURL?.path,
            insertText: { [weak self] value in
                guard let self else { return }
                self.applyPluginEdit(
                    range: self.currentTextView?.selectedRange() ?? self.currentSelection,
                    replacement: value
                )
            },
            replaceSelection: { [weak self] value in
                guard let self else { return }
                let range = self.currentTextView?.selectedRange() ?? self.currentSelection
                self.applyPluginEdit(range: range, replacement: value)
            },
            setText: { [weak self] value in
                guard let self else { return }
                self.document.text = value
                self.document.isDirty = true
                self.currentTextView?.setPlainText(value)
            },
            setSelection: { [weak self] location, length in
                guard let self else { return }
                let ns = self.document.text as NSString
                let safeLocation = min(max(0, location), ns.length)
                let safeLength = min(max(0, length), ns.length - safeLocation)
                let range = NSRange(location: safeLocation, length: safeLength)
                self.currentSelection = range
                self.currentTextView?.setSelectedRange(range)
                self.currentTextView?.scrollRangeToVisible(range)
            },
            save: { [weak self] in
                _ = self?.saveDocument()
            },
            alert: { [weak self] title, message in
                self?.presentInfo(title, message: message)
            },
            setAccent: { [weak self] hex in
                guard let self, AccentTheme.color(fromHex: hex) != nil else { return }
                self.settings.accent = .custom
                self.settings.accentHex = hex.hasPrefix("#") ? hex : "#" + hex
            },
            setPreviewTheme: { [weak self] name in
                guard let self else { return }
                let normalized = name.lowercased().replacingOccurrences(of: "-", with: "")
                let theme = PreviewTheme.allCases.first {
                    $0.rawValue.lowercased().replacingOccurrences(of: "-", with: "") == normalized
                }
                if let theme { self.settings.previewTheme = theme }
            },
            setAppearance: { [weak self] name in
                guard let self else { return }
                let normalized = name.lowercased().replacingOccurrences(of: "-", with: "")
                let appearance = AppAppearance.allCases.first {
                    $0.rawValue.lowercased().replacingOccurrences(of: "-", with: "") == normalized
                }
                if let appearance { self.settings.appearance = appearance }
            }
        )

        pluginHost.execute(commandID: command.id, context: context)
        if let error = pluginHost.lastError {
            presentInfo("Plugin error", message: error)
        }
        currentTextView?.window?.makeFirstResponder(currentTextView)
    }

    func exportWithPlugin(_ exporter: PluginExporterDescriptor) {
        let title = (document.displayName as NSString).deletingPathExtension
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exporter.fileExtension) ?? .html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (title.isEmpty ? "Untitled" : title) + "." + exporter.fileExtension
        panel.message = "Export using “\(exporter.title)” from \(exporter.pluginName)."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let html = pluginHost.exportHTML(
            exporterID: exporter.id,
            markdown: document.text,
            title: title.isEmpty ? "Untitled" : title,
            theme: settings.previewTheme
        ) else {
            presentInfo("Plugin export failed", message: pluginHost.lastError ?? "The exporter returned no output.")
            return
        }

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentError("Couldn’t export “\(url.lastPathComponent)”.", error: error)
        }
    }

    /// Applies a plugin edit through the focused text view so it participates in undo.
    private func applyPluginEdit(range: NSRange, replacement: String) {
        let ns = document.text as NSString
        let location = min(max(0, range.location), ns.length)
        let length = min(max(0, range.length), ns.length - location)
        let safeRange = NSRange(location: location, length: length)

        if let textView = currentTextView {
            textView.insertText(replacement, replacementRange: safeRange)
            let caret = safeRange.location + (replacement as NSString).length
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            textView.scrollRangeToVisible(NSRange(location: caret, length: 0))
            currentSelection = NSRange(location: caret, length: 0)
        } else {
            document.text = ns.replacingCharacters(in: safeRange, with: replacement)
            document.isDirty = true
            currentSelection = NSRange(
                location: safeRange.location + (replacement as NSString).length,
                length: 0
            )
        }
    }

    // MARK: - Quick capture

    /// Saves text from the menu-bar capture panel into the vault's Inbox folder.
    func saveQuickCapture(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let root = effectiveVaultRoot else {
            quickCaptureInNewTab(trimmed)
            return
        }

        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Capture " + formatter.string(from: Date()) + ".md"
        let url = inbox.appendingPathComponent(name)

        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try (trimmed + "\n").write(to: url, atomically: true, encoding: .utf8)
            open(url: url)
            refreshVault()
        } catch {
            presentError("Couldn’t save the capture.", error: error)
        }
    }

    /// Handles `iriseditor://capture?text=…` from Shortcuts or other apps.
    func handleCaptureURL(_ url: URL) {
        guard url.scheme == "iriseditor", url.host == "capture" else { return }
        let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "text" })?
            .value ?? ""
        if text.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            saveQuickCapture(text)
        }
    }

    private func quickCaptureInNewTab(_ text: String) {
        let captured = EditorDocument()
        captured.text = text
        captured.isDirty = true
        withAnimation(.snappy(duration: 0.25)) {
            tabs.append(captured)
            currentTabIndex = tabs.count - 1
            document = captured
        }
        NSApp.activate(ignoringOtherApps: true)
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
            VersionHistoryStore.record(text: target.text, fileURL: resolved)
            if let draftID = target.draftID {
                DraftStore.delete(id: draftID)
                target.draftID = nil
            }
            refreshVaultIfNeeded()
            saveSession()
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
            // "Don't Save" must actually discard the work: without this the
            // crash-recovery draft survives and reappears on the next launch.
            discardDraft(for: target)
            return true
        default:
            return false
        }
    }

    /// Deletes the crash-recovery draft backing an untitled document and detaches it, so
    /// text the user discarded can never be resurrected by session restoration.
    private func discardDraft(for target: EditorDocument) {
        guard let draftID = target.draftID else { return }
        DraftStore.delete(id: draftID)
        target.draftID = nil
    }

    /// Prompts for every dirty tab in order (used before quitting); false on cancel.
    func confirmDiscardAllTabs() -> Bool {
        for tab in tabs where tab.isDirty {
            guard confirmDiscardChanges(for: tab) else { return false }
        }
        if let side = secondDocument, side.isDirty {
            guard confirmDiscardChanges(for: side) else { return false }
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
        postToEditors(.goToLine, userInfo: ["line": line])
        closeFindPanel()
    }

    /// Jumps to a line from the outline or quick switcher, leaving preview-only mode so
    /// the caret is actually visible.
    func reveal(line: Int) {
        // Remember the target as well as broadcasting it: when `reveal` follows a
        // document switch the editor is still showing the *previous* text, and jumping
        // now would clamp the line against the old document and lose the position.
        pendingReveal = (document.id, line)

        let post = { [weak self] in
            guard let self else { return }
            self.postToEditors(.goToLine, userInfo: ["line": line])
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

    /// Called by an editor once it actually displays `documentID`; returns the pending
    /// jump line for that document and clears it.
    func takePendingReveal(for documentID: UUID) -> Int? {
        guard let pending = pendingReveal, pending.documentID == documentID else { return nil }
        pendingReveal = nil
        return pending.line
    }

    func clearPendingReveal(for documentID: UUID) {
        guard let pending = pendingReveal, pending.documentID == documentID else { return }
        pendingReveal = nil
    }

    /// Posts a document-scoped editor action so only the pane showing `document` reacts.
    private func postToEditors(_ name: Notification.Name, userInfo: [String: Any] = [:]) {
        var info = userInfo
        info["documentID"] = document.id
        NotificationCenter.default.post(name: name, object: nil, userInfo: info)
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
        postToEditors(
            .findHighlight,
            userInfo: ["ranges": [NSRange]()]
        )
    }

    private func postReplacement(ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }
        postToEditors(
            .replaceMatches,
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
        postToEditors(.findHighlight, userInfo: userInfo)
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
        refreshVaultIfNeeded()
    }

    func setSidebarPane(_ pane: VaultPane) {
        withAnimation(.snappy(duration: 0.22)) {
            sidebarTab = pane
            if !showOutline { showOutline = true }
        }
        refreshVaultIfNeeded()
    }

    func toggleZenMode() {
        withAnimation(.snappy(duration: 0.3)) {
            isZenMode.toggle()
        }
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    // MARK: - Keybindings

    /// Effective shortcut for a command, preferring the user override when valid.
    func keyboardShortcut(for command: KeybindingCommand) -> KeyboardShortcut? {
        guard let raw = settings.keybindingOverrides[command.rawValue] else {
            return command.defaultShortcut
        }
        return KeybindingParser.shortcut(from: raw) ?? command.defaultShortcut
    }

    /// Human-readable shortcut, e.g. `"\u{2303}\u{2318}Z"`, for Settings rows.
    func keybindingLabel(for command: KeybindingCommand) -> String {
        let raw = settings.keybindingOverrides[command.rawValue] ?? command.defaultKeyString
        return KeybindingParser.displayName(raw)
    }

    /// Stores a new shortcut, or clears it when `value` is nil. Returns false when the
    /// string cannot be parsed or lacks a command/control modifier.
    @discardableResult
    func setKeybindingOverride(_ value: String?, for command: KeybindingCommand) -> Bool {
        if let value {
            guard let normalized = KeybindingParser.normalized(value) else { return false }
            settings.keybindingOverrides[command.rawValue] = normalized
        } else {
            settings.keybindingOverrides.removeValue(forKey: command.rawValue)
        }
        settings.save()
        NotificationCenter.default.post(name: .keybindingOverrideApplied, object: command)
        return true
    }

    func resetKeybindings() {
        guard !settings.keybindingOverrides.isEmpty else { return }
        settings.keybindingOverrides.removeAll()
        settings.save()
        NotificationCenter.default.post(name: .keybindingOverrideApplied, object: nil)
    }

    // MARK: - Tabs

    /// Duplicates a tab as a new untitled document with the same contents.
    func duplicateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let source = tabs[index]
        let copy = EditorDocument()
        copy.text = source.text
        copy.fileURL = nil
        copy.isDirty = true

        withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
            tabs.insert(copy, at: min(index + 1, tabs.count))
            currentTabIndex = tabs.firstIndex(where: { $0.id == copy.id }) ?? 0
            document = copy
        }
        saveSession()
    }

    /// Drag-reorders a tab, keeping the active document selected.
    func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source) else { return }
        let target = min(max(0, destination), tabs.count - 1)
        guard source != target else { return }

        let active = document
        withAnimation(.snappy(duration: 0.24)) {
            let moved = tabs.remove(at: source)
            tabs.insert(moved, at: target)
            if let index = tabs.firstIndex(where: { $0.id == active.id }) {
                currentTabIndex = index
            }
        }
        saveSession()
    }

    // MARK: - Second pane

    func openInSecondPane(url: URL? = nil) {
        let targetURL = url ?? document.fileURL
        let side = EditorDocument()
        if let targetURL, let contents = Self.readText(at: targetURL) {
            side.text = contents
            side.fileURL = targetURL
            side.isDirty = false
        } else {
            side.text = document.text
            side.isDirty = true
        }
        withAnimation(.snappy(duration: 0.26)) {
            secondDocument = side
        }
    }

    func closeSecondPane() {
        withAnimation(.snappy(duration: 0.24)) {
            secondDocument = nil
        }
    }

    // MARK: - Vault

    private func refreshVault() {
        guard let root = effectiveVaultRoot else {
            vaultFiles = []
            vaultTags = []
            vaultBacklinks = []
            vaultGraph = VaultGraph(nodes: [], edges: [])
            return
        }

        lastVaultRoot = root.standardizedFileURL
        let capturedRoot = root
        let currentURL = document.fileURL

        vaultRefreshTask?.cancel()
        vaultRefreshTask = Task.detached(priority: .utility) { [weak self] in
            let files = VaultScanner.markdownFiles(in: capturedRoot)
            let tags = VaultScanner.tags(in: files)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.effectiveVaultRoot?.standardizedFileURL == capturedRoot.standardizedFileURL else {
                    return
                }
                self.vaultFiles = files
                self.vaultTags = tags
                self.vaultBacklinks = currentURL.map {
                    VaultScanner.backlinks(to: $0, in: files)
                } ?? []
                self.vaultGraph = VaultScanner.graph(around: currentURL, in: files)
                self.refreshTemplates()
                SpotlightIndexer.index(files: files)
            }
        }
    }

    /// Throttled refresh used by sidebar panes and file operations.
    func refreshVaultIfNeeded() {
        guard !vaultRefreshScheduled else { return }
        vaultRefreshScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self else { return }
            self.vaultRefreshScheduled = false
            self.refreshVault()
        }
    }

    func refreshBacklinks() {
        let url = document.fileURL
        vaultBacklinks = url.map { VaultScanner.backlinks(to: $0, in: vaultFiles) } ?? []
        vaultGraph = VaultScanner.graph(around: url, in: vaultFiles)
    }

    func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to use as your Iris vault."
        panel.prompt = "Use Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Drop results from the previous vault so stale notes stop appearing in
        // Spotlight once the index is repopulated for the new root.
        SpotlightIndexer.removeAll()
        vaultRootURL = url
        UserDefaults.standard.set(url.path, forKey: Self.vaultRootDefaultsKey)
        refreshVault()
    }

    func useCurrentFolderAsVault() {
        guard let folder = document.fileURL?.deletingLastPathComponent() else { return }
        vaultRootURL = folder
        UserDefaults.standard.set(folder.path, forKey: Self.vaultRootDefaultsKey)
        refreshVault()
    }

    private func refreshTemplates() {
        guard let root = effectiveVaultRoot else {
            vaultTemplates = []
            return
        }
        let folder = root.appendingPathComponent("Templates", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        vaultTemplates = contents
            .filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func openDailyNote() {
        guard let root = effectiveVaultRoot else {
            presentInfo(
                "No vault folder",
                message: "Save this document or choose a vault folder before creating a daily note."
            )
            return
        }

        let url = DailyNotes.noteURL(for: Date(), in: root)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try DailyNotes.defaultTemplate(date: Date())
                    .write(to: url, atomically: true, encoding: .utf8)
            } catch {
                presentError("Couldn’t create today’s note.", error: error)
                return
            }
        }
        open(url: url)
        refreshVault()
    }

    func applyTemplate(_ url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        insertSnippet(contents)
    }

    /// Creates a note next to the current file (or at the vault root) and opens it.
    func createNote() {
        guard let root = effectiveVaultRoot else {
            presentInfo(
                "No vault folder",
                message: "Choose a vault folder before creating notes."
            )
            return
        }

        guard let name = promptForName(title: "New Note", placeholder: "Note name") else {
            return
        }
        let base = (name as NSString).deletingPathExtension
        let fileName = base.isEmpty ? "Untitled" : base
        let url = root
            .appendingPathComponent(fileName)
            .appendingPathExtension(MarkdownFileType.defaultExtension)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            presentInfo("Note already exists", message: "“\(fileName)” is already in this folder.")
            return
        }

        do {
            try "# \(fileName)\n".write(to: url, atomically: true, encoding: .utf8)
            open(url: url)
            refreshVault()
        } catch {
            presentError("Couldn’t create the note.", error: error)
        }
    }

    func renameCurrentFile() {
        guard let url = document.fileURL else { return }
        let current = url.deletingPathExtension().lastPathComponent
        guard let name = promptForName(
            title: "Rename Note",
            placeholder: current,
            initial: current
        ) else { return }

        let base = (name as NSString).deletingPathExtension
        guard !base.isEmpty else { return }
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(base)
            .appendingPathExtension(MarkdownFileType.defaultExtension)

        do {
            try FileManager.default.moveItem(at: url, to: destination)
            document.fileURL = destination
            recordRecent(destination)
            refreshVault()
        } catch {
            presentError("Couldn’t rename the note.", error: error)
        }
    }

    func deleteCurrentFile() {
        guard let url = document.fileURL else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(url.lastPathComponent)”?"
        alert.informativeText = "This moves the file to the Trash."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            document.isDirty = false
            closeTab(at: currentTabIndex)
            refreshVault()
        } catch {
            presentError("Couldn’t delete the note.", error: error)
        }
    }

    // MARK: - Vault search

    func toggleVaultSearch() {
        withAnimation(.snappy(duration: 0.2)) {
            showVaultSearch.toggle()
        }
        if showVaultSearch {
            showCommandPalette = false
            showQuickSwitcher = false
        } else {
            vaultSearchQuery = ""
            vaultSearchResults = []
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    func updateVaultSearch(query: String) {
        vaultSearchGeneration += 1
        let generation = vaultSearchGeneration
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            vaultSearchResults = []
            return
        }
        let files = vaultFiles
        // Results are only accepted when they belong to the newest query, so a slow
        // search for "a" can never overwrite the results for a later "abc".
        Task.detached(priority: .userInitiated) { [weak self] in
            let results = VaultScanner.search(query, in: files)
            await MainActor.run {
                guard let self, self.vaultSearchGeneration == generation else { return }
                self.vaultSearchResults = results
            }
        }
    }

    // MARK: - Wiki autocomplete

    func updateWikiSuggestions(query: String) {
        let candidates = VaultScanner.allWikiTargets(in: vaultFiles)
        let normalized = query.lowercased().trimmingCharacters(in: .whitespaces)
        let matches: [String]
        if normalized.isEmpty {
            matches = Array(candidates.prefix(8))
        } else {
            matches = candidates
                .filter { $0.lowercased().contains(normalized) }
                .sorted { lhs, rhs in
                    let leftPrefix = lhs.lowercased().hasPrefix(normalized)
                    let rightPrefix = rhs.lowercased().hasPrefix(normalized)
                    if leftPrefix != rightPrefix { return leftPrefix }
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
        }
        wikiSuggestions = Array(matches.prefix(8))
        wikiSuggestionIndex = 0
        showWikiSuggestions = !wikiSuggestions.isEmpty
    }

    func dismissWikiSuggestions() {
        showWikiSuggestions = false
        wikiSuggestions = []
        wikiSuggestionIndex = 0
    }

    func moveWikiSuggestion(by delta: Int) {
        guard !wikiSuggestions.isEmpty else { return }
        wikiSuggestionIndex = (wikiSuggestionIndex + delta + wikiSuggestions.count)
            % wikiSuggestions.count
    }

    var selectedWikiSuggestion: String? {
        guard wikiSuggestions.indices.contains(wikiSuggestionIndex) else { return nil }
        return wikiSuggestions[wikiSuggestionIndex]
    }

    // MARK: - Version history

    func presentVersionHistory() {
        versionHistory = VersionHistoryStore.versions(for: currentVersionKey)
        withAnimation(.snappy(duration: 0.2)) {
            showVersionHistory = true
        }
    }

    func dismissVersionHistory() {
        withAnimation(.snappy(duration: 0.2)) {
            showVersionHistory = false
        }
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    var currentVersionKey: String {
        VersionHistoryStore.key(forFileURL: document.fileURL)
    }

    func restoreVersion(_ version: DocumentVersion) {
        document.text = version.text
        document.isDirty = true
        dismissVersionHistory()
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    func refreshVersionHistory() {
        versionHistory = VersionHistoryStore.versions(for: currentVersionKey)
    }

    // MARK: - Session

    func saveSession() {
        let session = EditorSession(
            openFiles: tabs.compactMap { $0.fileURL?.path },
            activeIndex: currentTabIndex,
            viewMode: viewMode.rawValue,
            sidebarVisible: showOutline,
            sidebarPane: sidebarTab.rawValue,
            vaultRoot: vaultRootURL?.path
        )
        SessionStore.save(session)
    }

    // MARK: - AI

    func requestInlineCompletion() {
        postToEditors(.aiInlineCompletionRequest)
    }

    func requestRewriteSelection() {
        postToEditors(.aiRewriteSelectionRequest)
    }

    func pasteAsMarkdown() {
        postToEditors(.pasteAsMarkdown)
    }

    func summarizeDocument() {
        let text = document.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        aiStatusMessage = "Summarizing…"
        isAIWorking = true
        Task { @MainActor in
            defer { isAIWorking = false }
            do {
                let summary = try await ai.summarize(text)
                presentInfo("Summary", message: summary)
                aiStatusMessage = nil
            } catch {
                aiStatusMessage = nil
                presentError("Summarize failed", error: error)
            }
        }
    }

    func generateTitleAndTags() {
        let target = document
        let text = target.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        aiStatusMessage = "Generating title and tags…"
        isAIWorking = true
        Task { @MainActor in
            defer { isAIWorking = false }
            do {
                let result = try await ai.titleAndTags(for: text)
                // The user may have switched tabs while we were awaiting: apply the
                // metadata to the document the request was made for, never to whatever
                // happens to be in front now.
                applyMetadata(title: result.title, tags: result.tags, to: target)
                aiStatusMessage = nil
            } catch {
                aiStatusMessage = nil
                presentError("Couldn’t generate metadata", error: error)
            }
        }
    }

    /// Rewrites (or inserts) the frontmatter block with the generated title and tags.
    private func applyMetadata(title: String, tags: [String], to target: EditorDocument) {
        let text = target.text
        let body = MarkdownFrontmatterParser.parse(text)?.body ?? text
        var lines: [String] = ["---", "title: \(title)"]
        if !tags.isEmpty {
            lines.append("tags:")
            for tag in tags {
                lines.append("  - \(tag)")
            }
        }
        lines.append("---")
        let updated = lines.joined(separator: "\n") + "\n\n" + body
        target.text = updated
        target.isDirty = true
    }

    private func promptForName(
        title: String,
        placeholder: String,
        initial: String = ""
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = placeholder
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func presentInfo(_ title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        postToEditors(
            .toggleMarkdownFormat,
            userInfo: ["prefix": prefix, "suffix": suffix]
        )
    }

    /// Inserts a Markdown snippet (e.g. a table template) at the current cursor position.
    func insertSnippet(_ text: String) {
        postToEditors(
            .insertSnippet,
            userInfo: ["text": text]
        )
    }

    /// Toggles a task list checkbox in the source from the preview, matching the item by its
    /// visible text. This keeps the preview interactive without exposing raw ranges to views.
    func toggleTask(text: String) {
        let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        let pattern = try? NSRegularExpression(
            pattern: #"^([ \t]*[-*+][ \t]+\[)([ xX])(\][ \t]+)(.*)$"#
        )
        var lines = document.text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            guard let match = pattern?.firstMatch(
                in: line,
                range: NSRange(location: 0, length: (line as NSString).length)
            ),
            let labelRange = Range(match.range(at: 4), in: line) else {
                continue
            }

            let label = String(line[labelRange]).trimmingCharacters(in: .whitespaces)
            guard label == target else { continue }

            guard let markerRange = Range(match.range(at: 2), in: line) else { return }
            let current = line[markerRange]
            lines[index] = line.replacingCharacters(
                in: markerRange,
                with: current == " " ? "x" : " "
            )
            document.text = lines.joined(separator: "\n")
            document.isDirty = true
            return
        }
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

        // Persist the session whenever the visible document layout changes.
        Publishers.MergeMany(
            $currentTabIndex.map { _ in () }.eraseToAnyPublisher(),
            $viewMode.map { _ in () }.eraseToAnyPublisher(),
            $showOutline.map { _ in () }.eraseToAnyPublisher(),
            $sidebarTab.map { _ in () }.eraseToAnyPublisher(),
            $vaultRootURL.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.saveSession()
        }
        .store(in: &cancellables)

        $vaultSearchQuery
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.updateVaultSearch(query: query)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .wikiAutocompleteRequest)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let query = note.userInfo?["query"] as? String else {
                    self?.dismissWikiSuggestions()
                    return
                }
                self?.updateWikiSuggestions(query: query)
            }
            .store(in: &cancellables)

        $document
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshBacklinks()
                self.refreshVersionHistory()
                self.refreshVaultIfNeeded()
            }
            .store(in: &cancellables)

        // `switchToLatest` (not `flatMap`): switching tabs must *cancel* the previous
        // document's text subscription. With `flatMap` the old inner publisher stayed
        // alive forever, keeping the closed document and its closure retained.
        let textChanges = $document
            .map { document in
                document.$text
                    .map { text in (id: document.id, text: text) }
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()

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
                // Do not persist uncommitted input-method text (for example Pinyin
                // candidates); committing triggers another change that saves normally.
                guard self.currentTextView?.isComposingText != true else { return }
                guard change.id == self.document.id,
                      self.document.isDirty,
                      let url = self.document.fileURL else {
                    return
                }
                _ = self.save(to: url)
            }
            .store(in: &cancellables)

        // The second pane is a real editor too: autosave it the same way, otherwise
        // everything typed there is lost when the pane closes or the app quits.
        $secondDocument
            .map { document -> AnyPublisher<(id: UUID, text: String), Never> in
                guard let document else { return Empty().eraseToAnyPublisher() }
                return document.$text
                    .map { text in (id: document.id, text: text) }
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] change in
                guard let self,
                      let side = self.secondDocument,
                      side.id == change.id,
                      side.isDirty,
                      let url = side.fileURL else { return }
                guard self.currentTextView?.isComposingText != true else { return }
                _ = self.save(side, to: url)
            }
            .store(in: &cancellables)

        // Crash recovery for untitled drafts: persist the buffer shortly after typing stops.
        // Only dirty text counts as recoverable work; after a discard the document is clean
        // and a late debounced write must not recreate the draft.
        textChanges
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] change in
                guard let self,
                      self.currentTextView?.isComposingText != true,
                      change.id == self.document.id,
                      self.document.fileURL == nil,
                      self.document.isDirty,
                      !change.text.isEmpty else {
                    return
                }
                if self.document.draftID == nil {
                    self.document.draftID = UUID()
                }
                guard let draftID = self.document.draftID else { return }
                DraftStore.save(Draft(
                    id: draftID,
                    title: self.document.displayName,
                    text: change.text,
                    updatedAt: Date(),
                    restoredFromFile: nil
                ))
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

        NotificationCenter.default.publisher(for: .cursorDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let location = note.userInfo?["selectionLocation"] as? Int,
                      let length = note.userInfo?["selectionLength"] as? Int else { return }
                self?.currentSelection = NSRange(location: location, length: length)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .editorModeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                let label = note.userInfo?["label"] as? String
                self?.editorModeLabel = (label?.isEmpty == false) ? label : nil
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
    static let wikiAutocompleteRequest = Notification.Name("IrisEditor.wikiAutocompleteRequest")
    static let wikiAutocompleteAccept = Notification.Name("IrisEditor.wikiAutocompleteAccept")
    static let aiInlineCompletionRequest = Notification.Name("IrisEditor.aiInlineCompletionRequest")
    static let aiRewriteSelectionRequest = Notification.Name("IrisEditor.aiRewriteSelectionRequest")
    static let pasteAsMarkdown = Notification.Name("IrisEditor.pasteAsMarkdown")
    static let keybindingOverrideApplied = Notification.Name("IrisEditor.keybindingOverrideApplied")
    static let editorModeDidChange = Notification.Name("IrisEditor.editorModeDidChange")
    static let resetEditorMode = Notification.Name("IrisEditor.resetEditorMode")
}
