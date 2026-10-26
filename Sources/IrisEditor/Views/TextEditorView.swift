import AppKit
import SwiftUI

struct TextEditorViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let settings: EditorSettings
    let documentID: UUID

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

    private let customTextStorage: NSTextStorage
    private var settings: EditorSettings
    private var appliedSettings: EditorSettings?
    private var cachedLineIndex: TextLineIndex?
    private var findHighlightRanges: [NSRange] = []
    private var currentFindRange: NSRange?
    private var markdownHighlights: [MarkdownHighlighter.Highlight] = []

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
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.makeFirstResponder(self)
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

        settings = newSettings

        if fontChanged || tabChanged {
            font = newSettings.font
            applyTextAttributes(newSettings)
        }

        appliedSettings = newSettings

        if highlightChanged {
            needsDisplay = true
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
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        if !isApplyingExternalText {
            postCursorPosition()
            recomputeMarkdownHighlights()
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
        let location = min(selectedRange().location, textLength)
        let lineIndex = lineIndexSnapshot()
        let line = lineIndex.lineNumber(atUTF16Index: location)
        let start = lineIndex.lineStart(forLine: line) ?? 0
        let column = max(1, location - start + 1)

        NotificationCenter.default.post(
            name: .cursorDidChange,
            object: self,
            userInfo: ["line": line, "column": column]
        )
    }

    @objc private func handleSelectionChange(_ notification: Notification) {
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        postCursorPosition()
    }

    // MARK: - Tab insertion

    override func insertTab(_ sender: Any?) {
        let spaces = String(repeating: " ", count: max(1, settings.tabWidth))
        insertText(spaces, replacementRange: selectedRange())
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

        breakUndoCoalescing()
        let selection = selectedRange()
        guard shouldChangeText(in: selection, replacementString: snippet) else { return }
        textStorage?.replaceCharacters(in: selection, with: snippet)
        didChangeText()

        let newLocation = selection.location + (snippet as NSString).length
        setSelectedRange(NSRange(location: newLocation, length: 0))
        scrollRangeToVisible(NSRange(location: newLocation, length: 0))
        window?.makeFirstResponder(self)
    }

    @objc private func handleFocusEditor(_ notification: Notification) {
        window?.makeFirstResponder(self)
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
        shouldChangeText(in: result.changedRange, replacementString: result.replacement)
        textStorage?.replaceCharacters(in: result.changedRange, with: result.replacement)
        didChangeText()
        setSelectedRange(result.selection)
        scrollRangeToVisible(result.selection)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawCurrentLine(in: dirtyRect)
        drawFindHighlights(in: dirtyRect)
        super.draw(dirtyRect)
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
