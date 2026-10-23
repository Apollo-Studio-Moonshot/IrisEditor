import SwiftUI
import AppKit

// MARK: - Editor Container

struct EditorContainer: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(12)
            
            TextEditorViewRepresentable(
                text: Binding(
                    get: { appState.document.text },
                    set: { newValue in
                        appState.document.text = newValue
                        appState.document.isDirty = true
                    }
                ),
                settings: appState.settings
            )
            .padding(16)
        }
    }
}

// MARK: - SwiftUI Representable

struct TextEditorViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let settings: EditorSettings
    
    func makeNSView(context: Context) -> IrisTextView {
        let textView = IrisTextView(settings: settings)
        textView.delegate = context.coordinator
        
        NotificationCenter.default.addObserver(
            forName: .goToLine,
            object: nil,
            queue: .main
        ) { notification in
            let line = notification.userInfo?["line"] as? Int
            Task { @MainActor in
                if let line {
                    textView.scrollToLine(line)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .findHighlight,
            object: nil,
            queue: .main
        ) { notification in
            let ranges = notification.userInfo?["ranges"] as? [NSRange]
            Task { @MainActor in
                if let ranges {
                    textView.highlightFindMatches(ranges)
                }
            }
        }
        
        return textView
    }
    
    func updateNSView(_ nsView: IrisTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
        }
        nsView.applySettings(settings)
        let len = (nsView.string as NSString).length
        nsView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: len),
            actualCharacterRange: nil
        )
        nsView.setNeedsDisplay(.infinite)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        nonisolated func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // textView.string is @MainActor, but NSTextView notifications fire on main queue
            // We're already on main queue so it's safe; wrap in MainActor task to satisfy compiler
            Task { @MainActor [text] in
                text.wrappedValue = textView.string
            }
        }
    }
}

// MARK: - Iris Text View with Line Numbers

@MainActor
final class IrisTextView: NSTextView {
    private var settings: EditorSettings
    private let lineNumberView: LineNumberView
    private var findHighlightRanges: [NSRange] = []
    
    init(settings: EditorSettings) {
        self.settings = settings
        
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        
        self.lineNumberView = LineNumberView()
        self.lineNumberView.layoutManager = layoutManager
        
        super.init(frame: .zero, textContainer: textContainer)
        commonInit()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func commonInit() {
        isVerticallyResizable = true
        isHorizontallyResizable = true
        
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
        
        backgroundColor = .clear
        textColor = NSColor.white.withAlphaComponent(0.9)
        insertionPointColor = NSColor.white
        
        font = settings.font
        
        isEditable = true
        isSelectable = true
        isRichText = false
        importsGraphics = false
        usesFindBar = false
        allowsUndo = true
        
        textContainerInset = NSSize(width: 8, height: 10)
        
        applySettings(settings)
        
        NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSelectionChange()
            }
        }
    }
    
    func applySettings(_ newSettings: EditorSettings) {
        self.settings = newSettings
        font = newSettings.font
        
        if newSettings.wordWrap {
            textContainer?.widthTracksTextView = true
            isHorizontallyResizable = false
        } else {
            textContainer?.widthTracksTextView = false
            isHorizontallyResizable = true
        }
        
        setNeedsDisplay(.infinite)
    }
    
    // MARK: - Line Number Management
    
    override func layout() {
        super.layout()
        updateLineNumberFrame()
    }
    
    private func updateLineNumberFrame() {
        guard let scrollView = enclosingScrollView else { return }
        let gutterWidth: CGFloat = settings.showLineNumbers ? 56 : 0
        
        if settings.showLineNumbers {
            if lineNumberView.superview == nil {
                scrollView.documentView = nil
                let containerView = NSView(frame: scrollView.contentView.bounds)
                containerView.autoresizingMask = NSView.AutoresizingMask(rawValue: 2 | 16) // flexible width + height
                
                lineNumberView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: containerView.bounds.height)
                // flexible top + height + not flexible right = right margin flexible
                lineNumberView.autoresizingMask = NSView.AutoresizingMask(rawValue: 4 | 16)
                lineNumberView.textView = self
                lineNumberView.font = font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                containerView.addSubview(lineNumberView)
                
                self.frame = NSRect(x: gutterWidth, y: 0, width: containerView.bounds.width - gutterWidth, height: containerView.bounds.height)
                self.autoresizingMask = NSView.AutoresizingMask(rawValue: 2 | 16)
                containerView.addSubview(self)
                
                scrollView.documentView = containerView
            } else {
                lineNumberView.setNeedsDisplay(.infinite)
            }
        } else {
            lineNumberView.removeFromSuperview()
            if let scrollView = enclosingScrollView, let docView = scrollView.documentView {
                self.frame = NSRect(x: 0, y: 0, width: docView.bounds.width, height: docView.bounds.height)
                self.autoresizingMask = NSView.AutoresizingMask(rawValue: 2 | 16)
            }
        }
    }
    
    // MARK: - Custom Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        if settings.highlightCurrentLine {
            drawCurrentLineHighlight(in: dirtyRect)
        }
        
        if !findHighlightRanges.isEmpty {
            drawFindHighlights(in: dirtyRect)
        }
        
        super.draw(dirtyRect)
    }
    
    private func drawCurrentLineHighlight(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let textLength = (string as NSString).length
        guard textLength > 0 else { return }
        
        let selectedRange = self.selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
        
        guard glyphRange.location < layoutManager.numberOfGlyphs else { return }
        
        var lineRange = NSRange(location: 0, length: 0)
        layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &lineRange)
        
        let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
        
        let highlightRect = NSRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height)
        NSColor.white.withAlphaComponent(0.06).setFill()
        highlightRect.fill()
    }
    
    private func drawFindHighlights(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let textLength = (string as NSString).length
        guard textLength > 0 else { return }
        
        for range in findHighlightRanges {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            NSColor.yellow.withAlphaComponent(0.3).setFill()
            rect.fill()
        }
    }
    
    func highlightFindMatches(_ ranges: [NSRange]) {
        findHighlightRanges = ranges
        setNeedsDisplay(.infinite)
    }
    
    // MARK: - Go To Line
    
    func scrollToLine(_ lineNumber: Int) {
        let text = self.string as NSString
        var charIndex = 0
        var currentLine = 1
        
        while charIndex < text.length && currentLine < lineNumber {
            if text.character(at: charIndex) == 10 {
                currentLine += 1
            }
            charIndex += 1
        }
        
        if charIndex < text.length {
            let range = NSRange(location: charIndex, length: 0)
            self.setSelectedRange(range)
            scrollRangeToVisible(range)
        }
    }
    
    private func handleSelectionChange() {
        setNeedsDisplay(.infinite)
        lineNumberView.setNeedsDisplay(.infinite)
    }
    
    // MARK: - Tab Handling
    
    override func insertTab(_ sender: Any?) {
        let tabString = String(repeating: " ", count: settings.tabWidth)
        textStorage?.replaceCharacters(in: selectedRange(), with: tabString)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Line Number View

final class LineNumberView: NSView {
    weak var textView: IrisTextView?
    var layoutManager: NSLayoutManager?
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        // Guard against empty text - no glyphs to draw
        guard (textView.string as NSString).length > 0 else {
            // Still draw background + border
            drawBackgroundAndBorder()
            return
        }
        
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        drawBackgroundAndBorder()
        
        let textStorage = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
        
        var lineNumber = 1
        var characterIndex = 0
        var lineGlyphRange = NSRange(location: 0, length: 0)
        
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        
        while characterIndex < textStorage.length {
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: characterIndex)
            if glyphIdx >= visibleGlyphRange.location && glyphIdx <= NSMaxRange(visibleGlyphRange) {
                break
            }
            if textStorage.character(at: characterIndex) == 10 {
                lineNumber += 1
            }
            characterIndex += 1
        }
        
        layoutManager.lineFragmentRect(forGlyphAt: visibleGlyphRange.location, effectiveRange: &lineGlyphRange)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.35),
            .paragraphStyle: paragraphStyle
        ]
        
        let cursorLineAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle
        ]
        
        var glyphIndex = visibleGlyphRange.location
        
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            
            let isCursorLine = glyphIndex <= glyphRange.location && NSMaxRange(lineGlyphRange) > glyphRange.location
            
            let lineNumberString = NSString(string: "\(lineNumber)")
            let drawRect = NSRect(
                x: 4,
                y: lineRect.minY + textView.textContainerInset.height - lineRect.height,
                width: bounds.width - 8,
                height: font.capHeight + 4
            )
            
            lineNumberString.draw(in: drawRect, withAttributes: isCursorLine ? cursorLineAttrs : attrs)
            
            glyphIndex = NSMaxRange(lineGlyphRange)
            lineNumber += 1
            
            if lineGlyphRange.length == 0 { break }
        }
        
        context?.restoreGState()
    }
    
    override var isFlipped: Bool { true }
    
    private func drawBackgroundAndBorder() {
        let bgRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        NSColor.white.withAlphaComponent(0.03).setFill()
        bgRect.fill()
        
        NSColor.white.withAlphaComponent(0.1).setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSMakePoint(bounds.width - 0.5, 0))
        borderPath.line(to: NSMakePoint(bounds.width - 0.5, bounds.height))
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
}
