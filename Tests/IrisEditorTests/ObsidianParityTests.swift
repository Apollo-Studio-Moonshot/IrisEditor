import Foundation
import Testing
@testable import IrisEditor

/// Covers the Obsidian-flavoured syntax that Iris renders natively: `==highlight==`,
/// callouts (`> [!note]`), and the table/quote interactions around them.
@Suite("Obsidian parity")
struct ObsidianParityTests {

    private func plain(_ text: String) -> String {
        MarkdownInlineParser(references: [:]).parse(text).plainText
    }

    /// Unwraps the children of the single blockquote a callout test writes.
    private func quoteChildren(_ markdown: String) throws -> [MarkdownBlock] {
        let blocks = MarkdownBlockParser.parse(markdown)
        guard case .blockQuote(let children)? = blocks.first else {
            Issue.record("expected a blockquote for \(markdown), got \(blocks)")
            return []
        }
        return children
    }

    // MARK: - ==highlight==

    @Test func parsesHighlight() {
        let inlines = MarkdownInlineParser(references: [:]).parse("a ==b== c")
        #expect(inlines.plainText == "a b c")
        #expect(inlines.contains { if case .highlight = $0 { return true } else { return false } })
    }

    @Test func highlightKeepsEmphasisNested() {
        let inlines = MarkdownInlineParser(references: [:]).parse("==**bold**==")
        #expect(inlines.plainText == "bold")
        guard case .highlight(let inner)? = inlines.first else {
            Issue.record("expected a highlight span, got \(inlines)")
            return
        }
        guard case .strong = inner.first else {
            Issue.record("expected nested strong, got \(inner)")
            return
        }
    }

    @Test func singleEqualsStaysText() {
        #expect(plain("a = b = c") == "a = b = c")
        // Only a run of exactly two equals signs opens a highlight.
        #expect(plain("x ===y=== z") == "x ===y=== z")
    }

    @Test func unclosedHighlightStaysText() {
        #expect(plain("a ==b") == "a ==b")
    }

    @Test func highlightInsideCodeSpanIsLiteral() {
        #expect(plain("`==x==`") == "==x==")
    }

    @Test func exportsHighlightAsMark() {
        let html = MarkdownHTMLExport.export(body: "a ==b== c")
        #expect(html.contains("<mark>b</mark>"))
        // A standalone document carries the stylesheet that styles <mark>.
        let page = MarkdownHTMLExport.document(from: "a ==b== c", title: "T")
        #expect(page.contains("mark {"))
    }

    // MARK: - Callouts

    @Test func parsesCalloutWithTitle() throws {
        let callout = try #require(MarkdownCallout.parse(try quoteChildren("> [!warning] Be careful\n> body text")))
        #expect(callout.kind == .warning)
        #expect(callout.title == "Be careful")
        #expect(!callout.isFoldable)
        #expect(callout.body.contains { block in
            if case .paragraph(let text) = block { return text.contains("body text") }
            return false
        })
    }

    @Test func calloutFallsBackToDefaultTitle() throws {
        let callout = try #require(MarkdownCallout.parse(try quoteChildren("> [!tip]\n> a tip")))
        #expect(callout.kind == .tip)
        #expect(callout.title == "Tip")
    }

    @Test func calloutAliasesResolve() {
        #expect(MarkdownCalloutKind.from("hint") == .tip)
        #expect(MarkdownCalloutKind.from("check") == .success)
        #expect(MarkdownCalloutKind.from("caution") == .warning)
        #expect(MarkdownCalloutKind.from("tldr") == .abstract)
        #expect(MarkdownCalloutKind.from("nonsense") == nil)
    }

    @Test func calloutFoldMarkers() throws {
        let collapsed = try #require(MarkdownCallout.parse(
            try quoteChildren("> [!note]- Collapsed\n> hidden")
        ))
        #expect(collapsed.isFoldable)
        #expect(collapsed.isCollapsed)

        let expanded = try #require(MarkdownCallout.parse(
            try quoteChildren("> [!note]+ Expanded\n> shown")
        ))
        #expect(expanded.isFoldable)
        #expect(!expanded.isCollapsed)
    }

    @Test func plainQuoteIsNotACallout() {
        #expect(MarkdownCallout.parse(MarkdownBlockParser.parse("> just a quote")) == nil)
        #expect(MarkdownCallout.parse(MarkdownBlockParser.parse("> [!unknown] x")) == nil)
    }

    @Test func exportsCalloutAsDetails() {
        let html = MarkdownHTMLExport.export(body: "> [!warning]- Heads up\n> careful")
        #expect(html.contains("class=\"callout callout-warning callout-foldable collapsed\""))
        #expect(html.contains("<summary>"))
        #expect(html.contains("Heads up"))
        #expect(html.contains("careful"))
        // A collapsed callout must not be `open`.
        #expect(!html.contains("callout-warning callout-foldable collapsed\" open"))
    }

    @Test func exportedCalloutTitleIsEscaped() {
        let html = MarkdownHTMLExport.export(body: "> [!note] <script>alert(1)</script>\n> x")
        #expect(!html.contains("<script>alert(1)</script>"))
    }

    // MARK: - Editor highlighting

    @Test func editorHighlightsBoldInsideCalloutLine() {
        let highlights = MarkdownHighlighter.highlights(in: "> [!note] **strong**")
        #expect(highlights.contains { $0.token == .strong })
    }
}
