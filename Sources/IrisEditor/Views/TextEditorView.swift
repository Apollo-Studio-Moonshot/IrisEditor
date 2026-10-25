import AppKit
import SwiftUI

struct TextEditorViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let settings: EditorSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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

        textView.setPlainText(text)
        applyLayoutMode(settings.wordWrap, textView: textView, scrollView: scrollView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? IrisTextView else {
            return
        }

        context.coordinator.text = $text

        if textView.string != text {
            textView.setPlainText(text)
        }

        textView.applySettings(settings)
        applyLayoutMode(settings.wordWrap, textView: textView, scrollView: nsView)
        nsView.rulersVisible = settings.showLineNumbers
        (nsView.verticalRulerView as? LineNumberRulerView)?.updateFont(settings.lineNumberFont)
    }

    private func applyLayoutMode(_ wrap: Bool, textView: IrisTextView, scrollView: NSScrollView) {
        let width = max(scrollView.contentSize.width, 1)

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

        init(text: Binding<String>) {
            self.text = text
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
        case .listMarker: return .systemGreen
        case .horizontalRule: return .systemGray
        }
    }

    // MARK: - External content

    func setPlainText(_ newText: String) {
        isApplyingExternalText = true
        let savedDelegate = delegate
        delegate = nil
        string = newText
        delegate = savedDelegate
        isApplyingExternalText = false

        applyTextAttributes(settings)
        undoManager?.removeAllActions()
        selectedRange = NSRange(location: 0, length: 0)
        scrollToBeginningOfDocument(nil)

        cachedLineIndex = nil
        findHighlightRanges = []
        currentFindRange = nil
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
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
    private func toggleMarkdownFormat(prefix: String, suffix: String) {
        let ns = string as NSString
        var range = selectedRange()

        // Expand an empty selection to the current word for convenience.
        if range.length == 0 {
            range = wordRangeAtCursor()
        }

        guard range.length > 0, NSMaxRange(range) <= ns.length else { return }

        let selected = ns.substring(with: range)
        let alreadyWrapped = selected.hasPrefix(prefix) && selected.hasSuffix(suffix)

        let replacement: String
        let newSelection: NSRange

        if alreadyWrapped {
            let innerStart = prefix.count
            let innerEnd = selected.count - suffix.count
            guard innerEnd >= innerStart else { return }
            let inner = (selected as NSString).substring(with: NSRange(location: innerStart, length: innerEnd - innerStart))
            replacement = inner
            newSelection = NSRange(location: range.location, length: inner.count)
        } else {
            replacement = prefix + selected + suffix
            newSelection = NSRange(location: range.location, length: replacement.count)
        }

        shouldChangeText(in: range, replacementString: replacement)
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(newSelection)
    }

    private func wordRangeAtCursor() -> NSRange {
        let ns = string as NSString
        let location = min(selectedRange().location, ns.length)
        guard location > 0 else {
            return NSRange(location: 0, length: min(1, ns.length))
        }

        let charSet = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_-"))
        var start = location
        while start > 0 {
            let scalar = UnicodeScalar(Int(ns.character(at: start - 1)))!
            if !charSet.contains(scalar) { break }
            start -= 1
        }

        var end = location
        while end < ns.length {
            let scalar = UnicodeScalar(Int(ns.character(at: end)))!
            if !charSet.contains(scalar) { break }
            end += 1
        }

        return start == end ? NSRange(location: location, length: 0) : NSRange(location: start, length: end - start)
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
