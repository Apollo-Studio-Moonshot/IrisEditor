import AppKit
import SwiftUI

struct TextEditorViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let settings: EditorSettings
    let documentID: UUID
    var fileURL: URL? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, documentID: documentID)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = IrisTextView(settings: settings)
        textView.documentURL = fileURL
        textView.delegate = context.coordinator
        textView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(scrollView.contentSize.width, 600),
                         height: max(scrollView.contentSize.height, 400))
        )

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = settings.showLineNumbers

        scrollView.documentView = textView
        context.coordinator.textView = textView

        let viewport = EditorViewportStore.viewport(for: documentID)
        textView.setPlainText(
            text,
            restoringSelection: viewport?.selection,
            scrollOrigin: viewport?.scrollOrigin
        )
        applyLayoutMode(settings.wordWrap, textView: textView, scrollView: scrollView, coordinator: context.coordinator)

        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        guard let textView = nsView.documentView as? IrisTextView,
              let documentID = coordinator.documentID else {
            return
        }
        EditorViewportStore.save(
            documentID: documentID,
            selection: textView.selectedRange(),
            scrollOrigin: nsView.contentView.bounds.origin
        )
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? IrisTextView else {
            return
        }

        context.coordinator.text = $text

        let isDocumentSwitch = context.coordinator.documentID != documentID
        if isDocumentSwitch {
            if let previousID = context.coordinator.documentID {
                EditorViewportStore.save(
                    documentID: previousID,
                    selection: textView.selectedRange(),
                    scrollOrigin: nsView.contentView.bounds.origin
                )
            }
            context.coordinator.documentID = documentID
        }

        if textView.string != text || isDocumentSwitch {
            let viewport = isDocumentSwitch ? EditorViewportStore.viewport(for: documentID) : nil
            textView.setPlainText(
                text,
                restoringSelection: viewport?.selection,
                scrollOrigin: viewport?.scrollOrigin
            )
        }

        textView.applySettings(settings)
        textView.documentURL = fileURL
        applyLayoutMode(settings.wordWrap, textView: textView, scrollView: nsView, coordinator: context.coordinator)
        nsView.rulersVisible = settings.showLineNumbers
        (nsView.verticalRulerView as? LineNumberRulerView)?.updateFont(settings.lineNumberFont)
    }

    private func applyLayoutMode(
        _ wrap: Bool,
        textView: IrisTextView,
        scrollView: NSScrollView,
        coordinator: Coordinator
    ) {
        let width = max(scrollView.contentSize.width, 1)
        guard coordinator.appliedWordWrap != wrap || abs(coordinator.appliedContentWidth - width) > 0.5 else {
            return
        }
        coordinator.appliedWordWrap = wrap
        coordinator.appliedContentWidth = width

        if wrap {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            textView.frame.size.width = width
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                            height: CGFloat.greatestFiniteMagnitude)
            if textView.frame.width < width {
                textView.frame.size.width = width
            }
            scrollView.hasHorizontalScroller = true
        }

        let length = (textView.string as NSString).length
        textView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: length),
            actualCharacterRange: nil
        )
        textView.needsDisplay = true
        scrollView.verticalRulerView?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: IrisTextView?
        var documentID: UUID?
        var appliedWordWrap: Bool?
        var appliedContentWidth: CGFloat = 0

        init(text: Binding<String>, documentID: UUID) {
            self.text = text
            self.documentID = documentID
        }

        nonisolated func textDidChange(_ notification: Notification) {
            _ = notification
            MainActor.assumeIsolated {
                guard let textView = self.textView,
                      !textView.isApplyingExternalText else {
                    return
                }
                if self.text.wrappedValue != textView.string {
                    self.text.wrappedValue = textView.string
                }
            }
        }
    }
}

/// Remembers the caret and scroll position for each open document so switching tabs or
/// changing view mode does not send the user back to the top of the file.
@MainActor
enum EditorViewportStore {
    struct Viewport {
        var selection: NSRange
        var scrollOrigin: NSPoint
    }

    private static var storage: [UUID: Viewport] = [:]

    static func save(documentID: UUID, selection: NSRange, scrollOrigin: NSPoint) {
        storage[documentID] = Viewport(selection: selection, scrollOrigin: scrollOrigin)
    }

    static func viewport(for documentID: UUID) -> Viewport? {
        storage[documentID]
    }

    static func remove(documentID: UUID) {
        storage[documentID] = nil
    }
}

final class IrisTextView: NSTextView {
    private(set) var isApplyingExternalText = false

    /// Folder used to save pasted or dropped images into `assets/`.
    var documentURL: URL?

    private let customTextStorage: NSTextStorage
    private var settings: EditorSettings
    private var appliedSettings: EditorSettings?
    private var cachedLineIndex: TextLineIndex?
    private var findHighlightRanges: [NSRange] = []
    private var currentFindRange: NSRange?
    private var markdownHighlights: [MarkdownHighlighter.Highlight] = []

    // Multi-cursor support
    private var extraCursors: [Int] = []

    // Wiki link autocomplete
    private var wikiTriggerLocation: Int?

    // AI ghost text
    private var ghostSuggestion: String?
    private var ghostAnchor: Int?
    private var aiTask: Task<Void, Never>?

    // Modal and Emacs editing
    private var vimEngine = VimEngine()
    private var emacsKillRing = ""
    private var emacsMark: Int?

    @MainActor private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "webp", "bmp"
    ]

    var lineNumberFont: NSFont {
        settings.lineNumberFont
    }

    init(settings: EditorSettings) {
        self.settings = settings

        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        self.customTextStorage = storage
        super.init(frame: .zero, textContainer: container)

        configureTextView()
        applySettings(settings)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureTextView() {
        isRichText = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        importsGraphics = false
        usesFindBar = false
        usesFontPanel = false
        smartInsertDeleteEnabled = false

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false

        drawsBackground = false
        backgroundColor = .clear
        textColor = .textColor
        insertionPointColor = .textColor
        selectedTextAttributes = [
            .backgroundColor: NSColor.selectedContentBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor
        ]

        textContainerInset = NSSize(width: 12, height: 12)
        textContainer?.lineFragmentPadding = 0
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGoToLine(_:)),
            name: .goToLine,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFindHighlight(_:)),
            name: .findHighlight,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReplacement(_:)),
            name: .replaceMatches,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFocusEditor(_:)),
            name: .focusEditor,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleMarkdownFormat(_:)),
            name: .toggleMarkdownFormat,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertSnippet(_:)),
            name: .insertSnippet,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWikiAutocompleteAccept(_:)),
            name: .wikiAutocompleteAccept,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAIInlineCompletion(_:)),
            name: .aiInlineCompletionRequest,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAIRewrite(_:)),
            name: .aiRewriteSelectionRequest,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePasteAsMarkdown(_:)),
            name: .pasteAsMarkdown,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResetEditorMode(_:)),
            name: .resetEditorMode,
            object: nil
        )

        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.tiff"),
            .string,
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.makeFirstResponder(self)
            AppState.shared.currentTextView = self
            postEditorMode()
        }
    }

    // MARK: - Settings

    func applySettings(_ newSettings: EditorSettings) {
        let previous = appliedSettings
        let fontChanged = previous == nil
            || previous?.fontFamily != newSettings.fontFamily
            || previous?.fontSize != newSettings.fontSize
        let tabChanged = previous == nil || previous?.tabWidth != newSettings.tabWidth
        let highlightChanged = previous?.highlightCurrentLine != newSettings.highlightCurrentLine
        let focusChanged = previous?.focusMode != newSettings.focusMode
        let editingModeChanged = previous?.editingMode != newSettings.editingMode

        settings = newSettings
        if editingModeChanged {
            vimEngine.reset()
            postEditorMode()
        }

        if fontChanged || tabChanged {
            font = newSettings.font
            applyTextAttributes(newSettings)
        }

        appliedSettings = newSettings

        if highlightChanged {
            needsDisplay = true
        }
        if focusChanged {
            recomputeMarkdownHighlights()
        }
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    private func applyTextAttributes(_ newSettings: EditorSettings) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = newSettings.tabInterval
        paragraph.tabStops = []
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: newSettings.font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph
        ]

        if let storage = textStorage {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }

        typingAttributes = attributes
        insertionPointColor = .textColor
    }

    // MARK: - Markdown syntax highlighting

    /// Recomputes Markdown syntax highlights and applies them as temporary attributes.
    func applyMarkdownHighlights(_ highlights: [MarkdownHighlighter.Highlight]) {
        markdownHighlights = highlights

        guard let layoutManager else { return }

        // Clear previous temporary attributes first.
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        for highlight in highlights {
            guard highlight.nsRange.location != NSNotFound,
                  highlight.nsRange.length > 0,
                  NSMaxRange(highlight.nsRange) <= (string as NSString).length else {
                continue
            }
            layoutManager.addTemporaryAttributes(
                [.foregroundColor: color(for: highlight.token)],
                forCharacterRange: highlight.nsRange
            )
        }

        needsDisplay = true
        applyFocusDimming()
    }

    /// Dims every paragraph except the one containing the caret when Focus Mode is on.
    private func applyFocusDimming() {
        guard settings.focusMode else { return }
        guard let layoutManager else { return }

        let ns = string as NSString
        let textLength = ns.length
        guard textLength > 0 else { return }

        let caret = min(selectedRange().location, textLength)
        let paragraph = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        let dim = NSColor.secondaryLabelColor.withAlphaComponent(0.32)

        let before = NSRange(location: 0, length: paragraph.location)
        if before.length > 0 {
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: dim,
                forCharacterRange: before
            )
        }

        let afterStart = NSMaxRange(paragraph)
        let after = NSRange(location: afterStart, length: textLength - afterStart)
        if after.length > 0 {
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: dim,
                forCharacterRange: after
            )
        }
    }

    private func color(for token: MarkdownHighlighter.Token) -> NSColor {
        switch token {
        case .heading: return .systemBlue
        case .emphasis: return .systemPurple
        case .strong: return .systemOrange
        case .inlineCode: return .systemPink
        case .fencedCode: return .systemPink
        case .blockquote: return .systemGray
        case .link: return .systemTeal
        case .wikiLink: return .systemIndigo
        case .listMarker: return .systemGreen
        case .horizontalRule: return .systemGray
        }
    }

    // MARK: - External content

    func setPlainText(
        _ newText: String,
        restoringSelection selection: NSRange? = nil,
        scrollOrigin: NSPoint? = nil
    ) {
        isApplyingExternalText = true
        let savedDelegate = delegate
        delegate = nil
        string = newText
        delegate = savedDelegate
        isApplyingExternalText = false

        applyTextAttributes(settings)
        undoManager?.removeAllActions()

        let textLength = (newText as NSString).length
        if let selection {
            let location = min(max(0, selection.location), textLength)
            let length = min(max(0, selection.length), textLength - location)
            selectedRange = NSRange(location: location, length: length)
        } else {
            selectedRange = NSRange(location: 0, length: 0)
        }

        cachedLineIndex = nil
        findHighlightRanges = []
        currentFindRange = nil
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true

        if let scrollOrigin, let scrollView = enclosingScrollView {
            layoutSubtreeIfNeeded()
            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let maxY = max(0, contentHeight - scrollView.contentSize.height)
            let clamped = NSPoint(x: 0, y: min(max(0, scrollOrigin.y), maxY))
            scrollView.contentView.scroll(to: clamped)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            scrollToBeginningOfDocument(nil)
        }

        postCursorPosition()
        recomputeMarkdownHighlights()
    }

    override func didChangeText() {
        super.didChangeText()
        cachedLineIndex = nil
        AppState.shared.currentTextView = self
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        if !isApplyingExternalText {
            postCursorPosition()
            recomputeMarkdownHighlights()
            updateWikiAutocompleteTrigger()
            if ghostSuggestion != nil { clearGhostSuggestion() }
        }
    }

    /// Recomputes highlights from the current string content.
    private func recomputeMarkdownHighlights() {
        let highlights = MarkdownHighlighter.highlights(in: string)
        applyMarkdownHighlights(highlights)
    }

    func lineIndexSnapshot() -> TextLineIndex {
        if let cachedLineIndex {
            return cachedLineIndex
        }
        let index = TextLineIndex(string)
        cachedLineIndex = index
        return index
    }

    // MARK: - Cursor

    private func postCursorPosition() {
        let textLength = (string as NSString).length
        let selection = selectedRange()
        let location = min(selection.location, textLength)
        let lineIndex = lineIndexSnapshot()
        let line = lineIndex.lineNumber(atUTF16Index: location)
        let start = lineIndex.lineStart(forLine: line) ?? 0
        let column = max(1, location - start + 1)

        NotificationCenter.default.post(
            name: .cursorDidChange,
            object: self,
            userInfo: [
                "line": line,
                "column": column,
                "selectionLocation": selection.location,
                "selectionLength": selection.length
            ]
        )
    }

    @objc private func handleSelectionChange(_ notification: Notification) {
        AppState.shared.currentTextView = self
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        postCursorPosition()

        if settings.focusMode {
            recomputeMarkdownHighlights()
        }
        if settings.typewriterMode, notification.object as? NSTextView === self {
            scrollCaretToCenter()
        }
        if ghostSuggestion != nil {
            clearGhostSuggestion()
        }
    }

    /// Keeps the caret line vertically centered while typing, like a typewriter.
    private func scrollCaretToCenter() {
        guard let layoutManager,
              let scrollView = enclosingScrollView,
              layoutManager.numberOfGlyphs > 0 else {
            return
        }

        let textLength = (string as NSString).length
        guard textLength > 0 else { return }
        let caret = min(selectedRange().location, textLength - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: caret)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)

        let targetY = rect.midY + textContainerOrigin.y - scrollView.contentSize.height / 2
        let maxY = max(0, frame.height - scrollView.contentSize.height)
        let clamped = min(max(0, targetY), maxY)
        let current = scrollView.contentView.bounds.origin

        guard abs(current.y - clamped) > 1 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: current.x, y: clamped))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Typing

    override func insertTab(_ sender: Any?) {
        if settings.smartTableNavigation, moveAcrossTable(forward: true) {
            return
        }
        let spaces = String(repeating: " ", count: max(1, settings.tabWidth))
        insertText(spaces, replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        if settings.smartTableNavigation, moveAcrossTable(forward: false) {
            return
        }
        super.insertBacktab(sender)
    }

    /// Moves the caret to the next/previous pipe-table cell, inserting a fresh row when the
    /// caret is in the last cell of the last row. Returns false outside a table.
    private func moveAcrossTable(forward: Bool) -> Bool {
        let ns = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lineRange)
        while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }

        let pipes = pipeOffsets(in: line)
        guard pipes.count >= 2 else { return false }

        let local = selection.location - lineRange.location
        guard local <= (line as NSString).length else { return false }

        if forward {
            if let nextPipe = pipes.first(where: { $0 > local }) {
                var target = nextPipe + 1
                let lineLength = (line as NSString).length
                while target < lineLength,
                      (line as NSString).character(at: target) == 0x20 {
                    target += 1
                }
                setCaret(lineRange.location + target)
                return true
            }

            // Last cell: continue to the next row, or append a fresh, column-aligned row.
            let nextStart = NSMaxRange(lineRange)
            if nextStart < ns.length {
                let nextLineRange = ns.lineRange(for: NSRange(location: nextStart, length: 0))
                var nextLine = ns.substring(with: nextLineRange)
                while nextLine.hasSuffix("\n") || nextLine.hasSuffix("\r") { nextLine.removeLast() }
                if pipeOffsets(in: nextLine).count >= 2 {
                    let firstPipe = pipeOffsets(in: nextLine).first ?? 0
                    setCaret(nextLineRange.location + firstPipe + 1)
                    return true
                }
            }

            let columns = max(1, pipes.count - 1)
            let emptyRow = "|" + String(repeating: "  |", count: columns)
            let insertion = "\n" + emptyRow
            insertText(insertion, replacementRange: NSRange(location: nextStart, length: 0))
            setCaret(nextStart + 1 + 1)
            return true
        }

        if let previousPipe = pipes.last(where: { $0 < local - 1 }) {
            var target = previousPipe + 1
            let lineLength = (line as NSString).length
            while target < lineLength,
                  (line as NSString).character(at: target) == 0x20 {
                target += 1
            }
            setCaret(lineRange.location + target)
            return true
        }

        // First cell: jump to the previous row's last cell when one exists.
        guard lineRange.location > 0 else { return true }
        let previousLineRange = ns.lineRange(
            for: NSRange(location: lineRange.location - 1, length: 0)
        )
        var previousLine = ns.substring(with: previousLineRange)
        while previousLine.hasSuffix("\n") || previousLine.hasSuffix("\r") { previousLine.removeLast() }
        let previousPipes = pipeOffsets(in: previousLine)
        if previousPipes.count >= 2 {
            let lastPipe = previousPipes[previousPipes.count - 1]
            setCaret(previousLineRange.location + lastPipe + 1)
        }
        return true
    }

    private func pipeOffsets(in line: String) -> [Int] {
        let ns = line as NSString
        var offsets: [Int] = []
        for index in 0..<ns.length where ns.character(at: index) == 0x7C {
            offsets.append(index)
        }
        return offsets
    }

    /// Appends the column-closing pipe when the user finishes a table row with one
    /// column fewer than the header. Only fires with smart table navigation enabled and
    /// only when typing lands at the end of a pipe-delimited row.
    private func autoCompleteTableRowIfNeeded() {
        guard settings.smartTableNavigation else { return }
        let selection = selectedRange()
        guard selection.length == 0 else { return }

        let ns = string as NSString
        guard selection.location <= ns.length else { return }
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lineRange)
        while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }

        let lineLength = (line as NSString).length
        guard lineLength > 0 else { return }

        guard let rowPattern = try? NSRegularExpression(pattern: #"^\|.*\|$"#),
              rowPattern.firstMatch(
                in: line,
                range: NSRange(location: 0, length: lineLength)
              ) != nil else { return }

        let local = selection.location - lineRange.location
        guard local == lineLength else { return }

        let columns = pipeOffsets(in: line).count - 1
        guard columns > 0 else { return }
        guard let headerColumns = tableHeaderColumns(endingBefore: lineRange.location, in: ns),
              columns == headerColumns - 1 else { return }

        breakUndoCoalescing()
        super.insertText(
            " |",
            replacementRange: NSRange(location: lineRange.location + lineLength, length: 0)
        )
    }

    /// Number of columns in the first row of the table block immediately above `location`.
    private func tableHeaderColumns(endingBefore location: Int, in ns: NSString) -> Int? {
        guard location > 0 else { return nil }
        var index = location - 1
        var headerColumns: Int?

        while index >= 0 {
            let range = ns.lineRange(for: NSRange(location: index, length: 0))
            var line = ns.substring(with: range)
            while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty { break }

            let pipes = pipeOffsets(in: line)
            guard line.hasPrefix("|"), line.hasSuffix("|"), pipes.count >= 2 else { break }
            headerColumns = pipes.count - 1

            guard range.location > 0 else { break }
            index = range.location - 1
        }

        return headerColumns
    }

    private func setCaret(_ location: Int) {
        let clamped = min(max(0, location), (string as NSString).length)
        setSelectedRange(NSRange(location: clamped, length: 0))
        scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }

    /// Continues Markdown lists and block quotes when Return is pressed. On an empty
    /// item the marker is removed instead, so Return exits the container.
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0 else {
            super.insertNewline(sender)
            return
        }

        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lineRange)
        while line.hasSuffix("\n") || line.hasSuffix("\r") {
            line.removeLast()
        }

        let caretOffset = selection.location - lineRange.location
        guard let action = MarkdownEditing.returnAction(forLine: line, caretOffset: caretOffset) else {
            super.insertNewline(sender)
            return
        }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        switch action {
        case .continueLine(let prefix):
            insertText("\n" + prefix, replacementRange: selection)
        case .endContainer(_, let indentation):
            let contentLength = (line as NSString).length
            insertText(
                indentation,
                replacementRange: NSRange(location: lineRange.location, length: contentLength)
            )
            let caret = lineRange.location + (indentation as NSString).length
            setSelectedRange(NSRange(location: caret, length: 0))
        }
        undoManager?.endUndoGrouping()
    }

    // MARK: - Notifications

    @objc private func handleGoToLine(_ notification: Notification) {
        guard let line = notification.userInfo?["line"] as? Int else { return }
        scrollToLine(line)
    }

    func scrollToLine(_ requestedLine: Int) {
        let index = lineIndexSnapshot()
        let line = min(max(1, requestedLine), index.lineCount)
        guard let start = index.lineStart(forLine: line) else { return }

        let textLength = (string as NSString).length
        let location = min(start, textLength)
        let range = NSRange(location: location, length: 0)
        setSelectedRange(range)
        scrollRangeToVisible(range)
        window?.makeFirstResponder(self)
    }

    @objc private func handleFindHighlight(_ notification: Notification) {
        let ranges = notification.userInfo?["ranges"] as? [NSRange] ?? []
        let current = notification.userInfo?["current"] as? NSRange
        let shouldScroll = notification.userInfo?["scroll"] as? Bool ?? false
        highlightFindMatches(ranges, current: current, scroll: shouldScroll)
    }

    func highlightFindMatches(_ ranges: [NSRange], current: NSRange?, scroll: Bool) {
        findHighlightRanges = ranges
        currentFindRange = current
        needsDisplay = true

        guard scroll, let current, current.location != NSNotFound else { return }
        setSelectedRange(current)
        scrollRangeToVisible(current)
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    @objc private func handleReplacement(_ notification: Notification) {
        guard let ranges = notification.userInfo?["ranges"] as? [NSRange],
              let replacement = notification.userInfo?["replacement"] as? String else {
            return
        }
        replace(ranges, with: replacement)
    }

    private func replace(_ ranges: [NSRange], with replacement: String) {
        guard isEditable else { return }

        let textLength = (string as NSString).length
        let validRanges = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 && NSMaxRange($0) <= textLength }
            .sorted { $0.location > $1.location }

        guard !validRanges.isEmpty else { return }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for range in validRanges {
            insertText(replacement, replacementRange: range)
        }
        undoManager?.endUndoGrouping()

        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    @objc private func handleInsertSnippet(_ notification: Notification) {
        guard let snippet = notification.userInfo?["text"] as? String else { return }

        let selection = selectedRange()
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        insertText(snippet, replacementRange: selection)
        undoManager?.endUndoGrouping()

        let newLocation = selection.location + (snippet as NSString).length
        setSelectedRange(NSRange(location: newLocation, length: 0))
        scrollRangeToVisible(NSRange(location: newLocation, length: 0))
        window?.makeFirstResponder(self)
    }

    @objc private func handleFocusEditor(_ notification: Notification) {
        window?.makeFirstResponder(self)
    }

    // MARK: - Wiki autocomplete

    private func updateWikiAutocompleteTrigger() {
        if settings.editingMode == .vim, vimEngine.mode != .insert {
            wikiTriggerLocation = nil
            NotificationCenter.default.post(name: .wikiAutocompleteRequest, object: self)
            return
        }
        guard settings.wikiAutocomplete else {
            wikiTriggerLocation = nil
            NotificationCenter.default.post(name: .wikiAutocompleteRequest, object: self)
            return
        }

        let selection = selectedRange()
        guard selection.length == 0 else {
            wikiTriggerLocation = nil
            NotificationCenter.default.post(name: .wikiAutocompleteRequest, object: self)
            return
        }

        let ns = string as NSString
        let caret = min(selection.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let beforeLength = caret - lineRange.location
        guard beforeLength >= 2 else {
            wikiTriggerLocation = nil
            NotificationCenter.default.post(name: .wikiAutocompleteRequest, object: self)
            return
        }

        let before = ns.substring(with: NSRange(location: lineRange.location, length: beforeLength)) as NSString
        var triggerOffset: Int?
        var index = before.length - 2
        while index >= 0 {
            if before.substring(with: NSRange(location: index, length: 2)) == "[[" {
                triggerOffset = index
                break
            }
            index -= 1
        }

        guard let triggerOffset else {
            wikiTriggerLocation = nil
            NotificationCenter.default.post(name: .wikiAutocompleteRequest, object: self)
            return
        }

        let query = before.substring(from: triggerOffset + 2)
        guard !query.contains("]]"), !query.contains("\n") else {
            wikiTriggerLocation = nil
            NotificationCenter.default.post(name: .wikiAutocompleteRequest, object: self)
            return
        }

        wikiTriggerLocation = lineRange.location + triggerOffset
        NotificationCenter.default.post(
            name: .wikiAutocompleteRequest,
            object: self,
            userInfo: ["query": query]
        )
    }

    @objc private func handleWikiAutocompleteAccept(_ notification: Notification) {
        guard let target = notification.userInfo?["target"] as? String,
              let trigger = wikiTriggerLocation else {
            return
        }

        let caret = selectedRange().location
        let range = NSRange(location: trigger, length: max(0, caret - trigger))
        let replacement = "[[\(target)]]"
        insertText(replacement, replacementRange: range)
        setCaret(range.location + (replacement as NSString).length)
        wikiTriggerLocation = nil
        AppState.shared.dismissWikiSuggestions()
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        AppState.shared.currentTextView = self

        if AppState.shared.showWikiSuggestions {
            switch keyCode {
            case 125: // Down
                AppState.shared.moveWikiSuggestion(by: 1)
                return
            case 126: // Up
                AppState.shared.moveWikiSuggestion(by: -1)
                return
            case 36, 48: // Return, Tab
                if let target = AppState.shared.selectedWikiSuggestion {
                    handleWikiAutocompleteAccept(Notification(
                        name: .wikiAutocompleteAccept,
                        object: self,
                        userInfo: ["target": target]
                    ))
                    return
                }
            case 53: // Escape
                wikiTriggerLocation = nil
                AppState.shared.dismissWikiSuggestions()
                return
            default:
                break
            }
        }

        if ghostSuggestion != nil, keyCode == 48, !event.modifierFlags.contains(.shift) {
            acceptGhostSuggestion()
            return
        }

        if keyCode == 53 {
            if !extraCursors.isEmpty {
                extraCursors = []
                needsDisplay = true
                return
            }
            if ghostSuggestion != nil {
                clearGhostSuggestion()
                return
            }
        }

        if settings.editingMode == .vim, handleVimKey(event) {
            return
        }

        if settings.editingMode == .emacs, handleEmacsKey(event) {
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Vim mode

    private func handleVimKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if vimEngine.mode == .insert {
            guard event.keyCode == 53 else { return false }
            let result = vimEngine.exitInsertMode(text: string, selection: selectedRange())
            applyVimResult(result)
            return true
        }

        // Leave menu shortcuts (⌘…), normal Option input, and non-redo Control chords
        // to AppKit. Control-R is the one Control key Vim owns in Normal mode.
        if flags.contains(.command) { return false }
        if flags.contains(.option) { return false }
        if flags.contains(.control), !(event.keyCode == 15 && !flags.contains(.shift)) {
            return false
        }

        let key: VimKey
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .returnKey
        case 51: key = .backspace
        case 15 where flags.contains(.control): key = .controlR
        default:
            guard let character = event.charactersIgnoringModifiers?.first else { return false }
            key = .character(character)
        }

        let result = vimEngine.handle(
            key: key,
            text: string,
            selection: selectedRange()
        )
        applyVimResult(result)
        return result.handled
    }

    private func applyVimResult(_ result: VimResult) {
        if result.text != string, let edit = Self.difference(from: string, to: result.text) {
            insertText(edit.replacement, replacementRange: edit.range)
        }

        let ns = string as NSString
        let location = min(max(0, result.selection.location), ns.length)
        let length = min(max(0, result.selection.length), ns.length - location)
        let selection = NSRange(location: location, length: length)
        setSelectedRange(selection)
        if selection.length == 0 {
            scrollRangeToVisible(selection)
        } else {
            scrollRangeToVisible(NSRange(location: selection.location, length: 0))
        }

        switch result.command {
        case .none:
            break
        case .save:
            _ = AppState.shared.saveDocument()
        case .closeTab:
            AppState.shared.closeTab(at: AppState.shared.currentTabIndex)
        case .saveAndClose:
            if AppState.shared.saveDocument() {
                AppState.shared.closeTab(at: AppState.shared.currentTabIndex)
            }
        case .undo:
            undoManager?.undo()
        case .redo:
            undoManager?.redo()
        case .openFind:
            AppState.shared.showFindReplace = true
        }

        postEditorMode()
    }

    private func postEditorMode() {
        let label: String
        switch settings.editingMode {
        case .vim:
            label = "VIM · \(vimEngine.statusText)"
        case .emacs:
            label = "EMACS"
        case .standard:
            label = ""
        }
        NotificationCenter.default.post(
            name: .editorModeDidChange,
            object: self,
            userInfo: ["label": label]
        )
    }

    @objc private func handleResetEditorMode(_ notification: Notification) {
        vimEngine.reset()
        postEditorMode()
    }

    /// Finds the smallest replacement that turns `old` into `new` so modal edits can
    /// flow through `insertText(_:replacementRange:)` and remain undoable.
    private static func difference(
        from old: String,
        to new: String
    ) -> (range: NSRange, replacement: String)? {
        let oldText = old as NSString
        let newText = new as NSString
        let shared = min(oldText.length, newText.length)

        var prefix = 0
        while prefix < shared, oldText.character(at: prefix) == newText.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < shared - prefix,
              oldText.character(at: oldText.length - 1 - suffix) == newText.character(at: newText.length - 1 - suffix) {
            suffix += 1
        }

        let oldRange = NSRange(location: prefix, length: oldText.length - prefix - suffix)
        let newRange = NSRange(location: prefix, length: newText.length - prefix - suffix)
        if oldRange.length == 0, newRange.length == 0 { return nil }
        return (oldRange, newText.substring(with: newRange))
    }

    // MARK: - Emacs mode

    private func handleEmacsKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command) else { return false }

        if flags.contains(.option) {
            switch event.keyCode {
            case 3: moveWordForward(nil)           // M-f
            case 11: moveWordBackward(nil)         // M-b
            case 2: deleteWordForward(nil)         // M-d
            case 51: deleteWordBackward(nil)       // M-Delete
            default: return false
            }
            return true
        }

        guard flags.contains(.control) else { return false }

        switch event.keyCode {
        case 0: moveToBeginningOfLine(nil)          // C-a
        case 14: moveToEndOfLine(nil)               // C-e
        case 3: moveForward(nil)                    // C-f
        case 11: moveBackward(nil)                  // C-b
        case 45: moveDown(nil)                      // C-n
        case 35: moveUp(nil)                        // C-p
        case 2: deleteForward(nil)                  // C-d
        case 40: killToEndOfLine()                  // C-k
        case 16: yankEmacsKillRing()                // C-y
        case 13: killEmacsRegionOrWord()            // C-w
        case 5: cancelEmacsCommand()                // C-g
        case 1: AppState.shared.showFindReplace = true // C-s
        case 44: undoManager?.undo()                // C-/
        case 49: emacsMark = selectedRange().location // C-Space
        default: return false
        }
        return true
    }

    private func killToEndOfLine() {
        let ns = string as NSString
        let selection = selectedRange()
        if selection.length > 0 {
            emacsKillRing = ns.substring(with: selection)
            insertText("", replacementRange: selection)
            return
        }

        let line = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
        var end = NSMaxRange(line)
        while end > line.location {
            let character = ns.character(at: end - 1)
            guard character == 10 || character == 13 else { break }
            end -= 1
        }
        let range = NSRange(location: selection.location, length: max(0, end - selection.location))
        guard range.length > 0 else { return }
        emacsKillRing = ns.substring(with: range)
        insertText("", replacementRange: range)
    }

    private func yankEmacsKillRing() {
        guard !emacsKillRing.isEmpty else { return }
        insertText(emacsKillRing, replacementRange: selectedRange())
    }

    private func killEmacsRegionOrWord() {
        let selection = selectedRange()
        if selection.length > 0 {
            emacsKillRing = (string as NSString).substring(with: selection)
            insertText("", replacementRange: selection)
            return
        }

        let ns = string as NSString
        let caret = min(selection.location, ns.length)
        var start = caret
        while start > 0, ![" ", "\t", "\n"].contains(ns.substring(with: NSRange(location: start - 1, length: 1))) {
            start -= 1
        }
        let range = NSRange(location: start, length: caret - start)
        guard range.length > 0 else { return }
        emacsKillRing = ns.substring(with: range)
        insertText("", replacementRange: range)
    }

    private func cancelEmacsCommand() {
        emacsMark = nil
        AppState.shared.showFindReplace = false
        AppState.shared.showGoToLine = false
        setSelectedRange(NSRange(location: selectedRange().location, length: 0))
    }

    // MARK: - AI

    @objc private func handleAIInlineCompletion(_ notification: Notification) {
        _ = notification
        aiTask?.cancel()

        let selection = selectedRange()
        let ns = string as NSString
        let caret = min(selection.location, ns.length)
        let anchor = caret

        let beforeStart = max(0, caret - 3000)
        let afterEnd = min(ns.length, caret + 800)
        let before = ns.substring(with: NSRange(location: beforeStart, length: caret - beforeStart))
        let after = ns.substring(with: NSRange(location: caret, length: afterEnd - caret))

        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let suggestion = try await AIAssistant.shared.complete(before: before, after: after)
                guard !Task.isCancelled,
                      !suggestion.isEmpty,
                      self.selectedRange().location == anchor else {
                    return
                }
                self.ghostSuggestion = suggestion
                self.ghostAnchor = anchor
                self.needsDisplay = true
                self.scrollRangeToVisible(NSRange(location: anchor, length: 0))
            } catch {
                self.presentAIError(error)
            }
        }
    }

    @objc private func handleAIRewrite(_ notification: Notification) {
        _ = notification
        let ns = string as NSString
        var range = selectedRange()
        if range.length == 0 {
            range = ns.paragraphRange(for: NSRange(location: min(range.location, ns.length), length: 0))
        }
        guard range.length > 0, NSMaxRange(range) <= ns.length else { return }
        let original = ns.substring(with: range)

        aiTask?.cancel()
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rewritten = try await AIAssistant.shared.rewrite(original, instruction: nil)
                guard !Task.isCancelled, !rewritten.isEmpty else { return }
                self.insertText(rewritten, replacementRange: range)
                self.scrollRangeToVisible(NSRange(location: range.location, length: (rewritten as NSString).length))
            } catch {
                self.presentAIError(error)
            }
        }
    }

    private func presentAIError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Writing assistant unavailable"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func acceptGhostSuggestion() {
        guard let ghost = ghostSuggestion, let anchor = ghostAnchor else { return }
        let length = (string as NSString).length
        let range = NSRange(location: min(anchor, length), length: 0)
        clearGhostSuggestion()
        insertText(ghost, replacementRange: range)
        setCaret(range.location + (ghost as NSString).length)
        window?.makeFirstResponder(self)
    }

    private func clearGhostSuggestion() {
        guard ghostSuggestion != nil else { return }
        ghostSuggestion = nil
        ghostAnchor = nil
        needsDisplay = true
    }

    // MARK: - Mouse, tasks, multi-cursor

    override func mouseDown(with event: NSEvent) {
        AppState.shared.currentTextView = self
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let point = convert(event.locationInWindow, from: nil)

        if flags.contains(.option) && flags.contains(.command) {
            let length = (string as NSString).length
            let index = min(max(0, characterIndexForInsertion(at: point)), length)
            extraCursors.append(index)
            extraCursors = Array(Set(extraCursors)).sorted()
            needsDisplay = true
            return
        }

        if flags.isEmpty, toggleTaskIfClicked(at: point) {
            return
        }

        if !extraCursors.isEmpty {
            extraCursors = []
            needsDisplay = true
        }
        super.mouseDown(with: event)
    }

    private func toggleTaskIfClicked(at point: NSPoint) -> Bool {
        guard let layoutManager,
              let container = textContainer,
              let storage = textStorage else {
            return false
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return false }

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: container)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return false }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        let ns = string as NSString
        guard characterIndex <= ns.length else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: characterIndex, length: 0))
        let line = ns.substring(with: lineRange) as NSString

        let pattern = try? NSRegularExpression(
            pattern: #"^([ \t]*[-*+][ \t]+)(\[)([ xX])(\])"#
        )
        guard let match = pattern?.firstMatch(
            in: line as String,
            range: NSRange(location: 0, length: line.length)
        ) else { return false }

        let boxRange = match.range(at: 3)
        let absolute = NSRange(location: lineRange.location + boxRange.location, length: 1)
        guard absolute.contains(characterIndex) else { return false }

        let current = line.substring(with: boxRange)
        let updated = current == " " ? "x" : " "
        storage.replaceCharacters(in: absolute, with: updated)
        didChangeText()
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        return true
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if settings.editingMode == .vim, vimEngine.mode != .insert {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        guard !extraCursors.isEmpty,
              let value = insertString as? String,
              !value.isEmpty,
              replacementRange.location != NSNotFound,
              replacementRange.length == 0 else {
            super.insertText(insertString, replacementRange: replacementRange)
            autoCompleteTableRowIfNeeded()
            return
        }

        let primary = replacementRange.location
        var positions = ([primary] + extraCursors).sorted()
        positions = positions.reduce(into: [Int]()) { result, value in
            if result.last != value { result.append(value) }
        }
        guard positions.count > 1 else {
            super.insertText(insertString, replacementRange: replacementRange)
            autoCompleteTableRowIfNeeded()
            return
        }

        let delta = (value as NSString).length
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        var newPositions: [Int] = []
        for (offset, position) in positions.enumerated() {
            let insertionPoint = position + offset * delta
            super.insertText(value, replacementRange: NSRange(location: insertionPoint, length: 0))
            newPositions.append(insertionPoint + delta)
        }
        undoManager?.endUndoGrouping()

        let primaryIndex = positions.firstIndex(of: primary) ?? positions.count - 1
        let newPrimary = newPositions[primaryIndex]
        extraCursors = newPositions.enumerated()
            .filter { $0.offset != primaryIndex }
            .map(\.element)
        setSelectedRange(NSRange(location: newPrimary, length: 0))
        needsDisplay = true
        autoCompleteTableRowIfNeeded()
    }

    override func deleteBackward(_ sender: Any?) {
        guard !extraCursors.isEmpty else {
            super.deleteBackward(sender)
            return
        }

        let primary = selectedRange()
        var deletions: [NSRange] = []

        if primary.length > 0 {
            deletions.append(primary)
        } else if primary.location > 0 {
            deletions.append(NSRange(location: primary.location - 1, length: 1))
        }
        for cursor in extraCursors where cursor > 0 {
            deletions.append(NSRange(location: cursor - 1, length: 1))
        }
        guard !deletions.isEmpty else { return }

        let originalExtras = extraCursors
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for range in deletions.sorted(by: { $0.location > $1.location }) {
            super.insertText("", replacementRange: range)
        }
        undoManager?.endUndoGrouping()

        let primaryShift = deletions.filter { $0.location < primary.location }.count
        let newPrimary = max(0, primary.location - primaryShift)
        extraCursors = originalExtras.compactMap { cursor in
            let shift = deletions.filter { $0.location < cursor }.count
            let updated = cursor - shift
            return updated > 0 ? updated : nil
        }
        setSelectedRange(NSRange(location: newPrimary, length: 0))
        needsDisplay = true
    }

    // MARK: - Images

    override func paste(_ sender: Any?) {
        if insertImages(from: .general) {
            return
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if insertImages(from: sender.draggingPasteboard) {
            return true
        }
        return super.performDragOperation(sender)
    }

    private func insertImages(from pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] {
            let images = urls.filter {
                $0.isFileURL && Self.imageExtensions.contains($0.pathExtension.lowercased())
            }
            if !images.isEmpty {
                var markdown: [String] = []
                for url in images {
                    if let relative = importImage(at: url) {
                        markdown.append("![](" + relative + ")")
                    }
                }
                if !markdown.isEmpty {
                    insertMarkdown(markdown.joined(separator: "\n") + "\n")
                    return true
                }
            }
        }

        let pngType = NSPasteboard.PasteboardType("public.png")
        let tiffType = NSPasteboard.PasteboardType("public.tiff")
        if let data = pasteboard.data(forType: pngType) ?? pasteboard.data(forType: tiffType),
           let image = NSImage(data: data),
           let relative = saveImage(image) {
            insertMarkdown("![](" + relative + ")\n")
            return true
        }
        return false
    }

    private func importImage(at url: URL) -> String? {
        guard let folder = assetsFolder() else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let destination = uniqueURL(in: folder, base: base, extension: ext)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            return nil
        }
        return markdownPath(for: destination)
    }

    private func saveImage(_ image: NSImage) -> String? {
        guard let folder = assetsFolder(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let destination = uniqueURL(in: folder, base: "image", extension: "png")
        do {
            try png.write(to: destination)
        } catch {
            return nil
        }
        return markdownPath(for: destination)
    }

    private func assetsFolder() -> URL? {
        let folder: URL
        if let documentURL {
            folder = documentURL.deletingLastPathComponent()
                .appendingPathComponent("assets", isDirectory: true)
        } else {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("IrisAssets", isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    private func uniqueURL(in folder: URL, base: String, extension ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder
                .appendingPathComponent("\(base)-\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private func markdownPath(for destination: URL) -> String {
        guard let documentURL else { return destination.path }
        let folder = documentURL.deletingLastPathComponent()
        let assets = folder.appendingPathComponent("assets", isDirectory: true)
        if destination.path.hasPrefix(assets.path + "/") {
            return "assets/" + destination.lastPathComponent
        }
        return destination.path
    }

    private func insertMarkdown(_ markdown: String) {
        let selection = selectedRange()
        insertText(markdown, replacementRange: selection)
        let length = (markdown as NSString).length
        setCaret(selection.location + length)
    }

    // MARK: - Paste as Markdown

    @objc private func handlePasteAsMarkdown(_ notification: Notification) {
        pasteAsMarkdown()
    }

    func pasteAsMarkdown() {
        let pasteboard = NSPasteboard.general
        if let html = pasteboard.string(forType: .html), !html.isEmpty {
            let markdown = HTMLToMarkdown.convert(html)
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        if let text = pasteboard.string(forType: .string) {
            insertText(text, replacementRange: selectedRange())
        }
    }

    @objc private func handleToggleMarkdownFormat(_ notification: Notification) {
        guard let prefix = notification.userInfo?["prefix"] as? String,
              let suffix = notification.userInfo?["suffix"] as? String else {
            return
        }
        toggleMarkdownFormat(prefix: prefix, suffix: suffix)
    }

    /// Wraps the current selection with Markdown markers, or un-wraps if already wrapped.
    /// Delegates all marker/word logic to `MarkdownFormatting`, which is grapheme-safe.
    private func toggleMarkdownFormat(prefix: String, suffix: String) {
        guard let result = MarkdownFormatting.toggle(
            text: string,
            selection: selectedRange(),
            prefix: prefix,
            suffix: suffix
        ) else {
            return
        }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        insertText(result.replacement, replacementRange: result.changedRange)
        undoManager?.endUndoGrouping()
        setSelectedRange(result.selection)
        scrollRangeToVisible(result.selection)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawCurrentLine(in: dirtyRect)
        drawFindHighlights(in: dirtyRect)
        super.draw(dirtyRect)
        drawExtraCarets()
        drawGhostSuggestion()
    }

    private func drawExtraCarets() {
        guard !extraCursors.isEmpty, let layoutManager, layoutManager.numberOfGlyphs > 0 else {
            return
        }
        NSColor.controlAccentColor.setFill()
        for cursor in extraCursors {
            guard let caret = caretGeometry(at: cursor) else { continue }
            NSRect(x: caret.x - 1, y: caret.y + 2, width: 2, height: max(4, caret.height - 4)).fill()
        }
    }

    private func drawGhostSuggestion() {
        guard let ghost = ghostSuggestion,
              let anchor = ghostAnchor,
              let caret = caretGeometry(at: anchor) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: settings.font,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        ]
        let ghostString = ghost as NSString
        let width = ghostString.size(withAttributes: attributes).width
        let maxX = bounds.width - 12
        let drawX = min(caret.x, max(0, maxX - width))
        ghostString.draw(
            at: NSPoint(x: drawX, y: caret.y),
            withAttributes: attributes
        )
    }

    private func caretGeometry(at location: Int) -> (x: CGFloat, y: CGFloat, height: CGFloat)? {
        guard let layoutManager, let container = textContainer,
              layoutManager.numberOfGlyphs > 0 else {
            return nil
        }

        let textLength = (string as NSString).length
        let clamped = min(max(0, location), textLength)
        let origin = textContainerOrigin

        if clamped >= textLength {
            let glyph = layoutManager.numberOfGlyphs - 1
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let bounds = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1),
                in: container
            )
            return (bounds.maxX + origin.x, rect.minY + origin.y, rect.height)
        }

        let glyph = layoutManager.glyphIndexForCharacter(at: clamped)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let point = layoutManager.location(forGlyphAt: glyph)
        return (point.x + origin.x, rect.minY + origin.y, rect.height)
    }

    private func drawCurrentLine(in dirtyRect: NSRect) {
        guard settings.highlightCurrentLine,
              let layoutManager,
              layoutManager.numberOfGlyphs > 0 else {
            return
        }

        let textLength = (string as NSString).length
        let caret = min(selectedRange().location, max(0, textLength - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: caret)

        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        lineRect.origin.x = 0
        lineRect.origin.y += textContainerOrigin.y
        lineRect.size.width = bounds.width

        guard lineRect.intersects(dirtyRect) else { return }

        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        lineRect.fill()
    }

    private func drawFindHighlights(in dirtyRect: NSRect) {
        guard !findHighlightRanges.isEmpty,
              let layoutManager,
              let textContainer else {
            return
        }

        let textLength = (string as NSString).length
        let origin = textContainerOrigin
        let current = currentFindRange

        for range in findHighlightRanges {
            guard range.location != NSNotFound,
                  range.length > 0,
                  NSMaxRange(range) <= textLength else {
                continue
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                var highlightRect = rect
                highlightRect.origin.x += origin.x
                highlightRect.origin.y += origin.y
                highlightRect = highlightRect.insetBy(dx: -1, dy: -1)

                guard highlightRect.intersects(dirtyRect) else { return }

                let color = range == current
                    ? NSColor.findHighlightColor.withAlphaComponent(0.70)
                    : NSColor.findHighlightColor.withAlphaComponent(0.35)
                color.setFill()
                NSBezierPath(roundedRect: highlightRect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: IrisTextView?
    private var numberFont: NSFont

    init(textView: IrisTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.numberFont = textView.lineNumberFont
        super.init(scrollView: scrollView, orientation: .verticalRuler)

        clientView = textView
        ruleThickness = 52

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var isFlipped: Bool { true }
    override var requiredThickness: CGFloat { 52 }

    func updateFont(_ font: NSFont) {
        numberFont = font
        needsDisplay = true
    }

    @objc private func clipBoundsChanged(_ notification: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.025).setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.lineWidth = 1
        separator.stroke()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        let lineIndex = textView.lineIndexSnapshot()
        let currentLine = lineIndex.lineNumber(
            atUTF16Index: textView.selectedRange().location
        )
        let drawRectWidth = max(0, bounds.width - 10)

        let textLength = (textView.string as NSString).length
        if textLength == 0 {
            let point = convert(
                NSPoint(x: 0, y: textView.textContainerOrigin.y),
                from: textView
            )
            let number = "1" as NSString
            let size = number.size(withAttributes: attributes)
            number.draw(
                in: NSRect(x: 0, y: point.y, width: drawRectWidth, height: size.height),
                withAttributes: attributes
            )
            return
        }

        let visibleRect = textView.visibleRect.offsetBy(
            dx: -textView.textContainerOrigin.x,
            dy: -textView.textContainerOrigin.y
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location < layoutManager.numberOfGlyphs else { return }

        var lastLine = 0

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, fragmentRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentRange.location)
            let line = lineIndex.lineNumber(atUTF16Index: characterIndex)
            guard line != lastLine else { return }
            lastLine = line

            let point = self.convert(
                NSPoint(x: 0, y: lineRect.minY + textView.textContainerOrigin.y),
                from: textView
            )
            guard point.y + lineRect.height >= self.bounds.minY,
                  point.y <= self.bounds.maxY else {
                return
            }

            let number = "\(line)" as NSString
            let textAttributes = line == currentLine ? currentAttributes : attributes
            let size = number.size(withAttributes: textAttributes)
            let y = point.y + (lineRect.height - size.height) / 2

            number.draw(
                in: NSRect(x: 0, y: y, width: drawRectWidth, height: size.height),
                withAttributes: textAttributes
            )
        }
    }
}
