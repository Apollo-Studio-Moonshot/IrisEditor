import Foundation
import Testing
@testable import IrisEditor

/// Regression tests for the audit findings in HTML export, inline parsing, `HTMLToMarkdown`,
/// and the document outline.
struct RegressionMarkdownAndExportTests {

    private func html(_ markdown: String) -> String {
        MarkdownHTMLExport.export(body: markdown, using: .system)
    }

    @Test func javascriptLinkIsDropped() {
        let out = html("[click](javascript:alert(1))")
        #expect(!out.lowercased().contains("javascript:"), "out=\(out)")
    }

    @Test func imageAltAttributeIsEscaped() {
        let out = html("![a\" onerror=\"alert(1)](https://example.com/x.png)")
        #expect(!out.contains("onerror=\"alert(1)\""), "out=\(out)")
    }

    @Test func codeFenceLanguageIsEscaped() {
        let out = html("```\"><img src=x onerror=alert(1)>\ncode\n```")
        #expect(!out.contains("<img src=x"), "out=\(out)")
    }

    @Test func headingTextIsEscaped() {
        let out = html("# <script>alert(1)</script>")
        #expect(!out.contains("<script>"), "out=\(out)")
    }

    @Test func codeBlockContentIsEscaped() {
        let out = html("```\n<script>alert(1)</script>\n```")
        #expect(!out.contains("<script>alert"), "out=\(out)")
    }

    @Test func wikiLinkHref() {
        let out = html("[[Some Note#Heading]]")
        #expect(out.contains("Some Note.md#Heading"), "out=\(out)")
    }
}

struct BugProbeInlineTests {

    @Test func nestedEmphasis() {
        let node = MarkdownInlineParser().parse("**a*b**")
        #expect(node.plainText == "a*b", "plain=\(node.plainText.debugDescription)")
    }

    @Test func strongAroundCode() {
        let node = MarkdownInlineParser().parse("**`code`**")
        #expect(node.plainText == "code", "plain=\(node.plainText.debugDescription)")
    }

    @Test func autolinkNotConfusedWithHTML() {
        let node = MarkdownInlineParser().parse("<https://example.com>")
        #expect(node.plainText == "https://example.com", "plain=\(node.plainText.debugDescription)")
    }

    @Test func escapedPipeInTable() {
        let blocks = MarkdownBlockParser.parse("| a |\n| --- |\n| x \\| y |\n")
        guard case let .table(_, _, rows)? = blocks.first else {
            #expect(Bool(false), "not a table: \(blocks)")
            return
        }
        #expect(rows.first == ["x | y"], "rows=\(rows)")
    }

    @Test func imageInsideLink() {
        let node = MarkdownInlineParser().parse("[![alt](img.png)](https://example.com)")
        #expect(node.plainText == "alt", "plain=\(node.plainText.debugDescription)")
    }
}

struct BugProbeHTMLToMarkdownTests {

    @Test func convertsBasicHTML() {
        let out = HTMLToMarkdown.convert("<h1>Title</h1><p>Some <strong>bold</strong> text</p>")
        #expect(out.contains("# Title"), "out=\(out.debugDescription)")
        #expect(out.contains("**bold**"), "out=\(out.debugDescription)")
    }

    @Test func convertsListAndLink() {
        let out = HTMLToMarkdown.convert("<ul><li>a</li><li>b</li></ul><a href=\"https://x.y\">l</a>")
        #expect(out.contains("- a"), "out=\(out.debugDescription)")
        #expect(out.contains("[l](https://x.y)"), "out=\(out.debugDescription)")
    }

    @Test func nestedListIndentation() {
        let out = HTMLToMarkdown.convert("<ul><li>a<ul><li>b</li></ul></li></ul>")
        #expect(out.contains("  - b") || out.contains("- b"), "out=\(out.debugDescription)")
    }
}

struct BugProbeOutlineTests {

    @Test func ignoresHeadingsInFences() {
        let text = "# Real\n\n```\n# Fake\n```\n"
        let headings = MarkdownOutline.headings(in: text)
        #expect(headings.map(\.title) == ["Real"], "headings=\(headings.map(\.title))")
    }

    @Test func setextHeadings() {
        let text = "Title\n=====\n\nSub\n---\n"
        let headings = MarkdownOutline.headings(in: text)
        #expect(headings.map(\.level) == [1, 2], "headings=\(headings)")
    }

    @Test func frontmatterHeadingNotCounted() {
        let text = "---\ntitle: x\n---\n\n# Real\n"
        let headings = MarkdownOutline.headings(in: text)
        #expect(headings.map(\.title) == ["Real"], "headings=\(headings.map(\.title))")
    }
}
