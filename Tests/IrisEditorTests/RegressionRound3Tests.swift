import Foundation
import Testing
@testable import IrisEditor

/// Emphasis delimiter pairing (CommonMark "rule of 3") and frontmatter handling.
struct RegressionEmphasisTests {

    private func plain(_ markdown: String) -> String {
        MarkdownInlineParser().parse(markdown).plainText
    }

    @Test func matrix() {
        let cases: [(String, String)] = [
            ("**a*b**", "a*b"),
            ("*a**b***", "ab"),
            ("**a**b**", "ab**"),
            ("a**b**c", "abc"),
            ("**bold *italic***", "bold italic"),
            ("_a_b_", "a_b"),
            ("~~strike~~", "strike"),
            ("**a b**", "a b"),
            ("***x***", "x"),
            ("*a **b** c*", "a b c"),
        ]
        var failures: [String] = []
        for (input, expected) in cases {
            let actual = plain(input)
            if actual != expected {
                failures.append("\(input.debugDescription) -> \(actual.debugDescription) (expected \(expected.debugDescription))")
            }
        }
        #expect(failures.isEmpty, "failures=\(failures)")
    }
}

struct BugProbeLinkTests {

    private func plain(_ markdown: String) -> String {
        MarkdownInlineParser().parse(markdown).plainText
    }

    @Test func linkWithParenthesesInURL() {
        #expect(plain("[x](https://example.com/a_(b))") == "x", "plain=\(plain("[x](https://example.com/a_(b))"))")
    }

    @Test func referenceLinkStyles() {
        let parser = MarkdownInlineParser()
        _ = parser
        let text = """
        [full][ref] and [collapsed][] and [shortcut]

        [ref]: https://a.example
        [collapsed]: https://b.example
        [shortcut]: https://c.example
        """
        let document = MarkdownBlockParser.parseDocument(text)
        let paragraphText: String
        if case let .paragraph(t)? = document.blocks.first { paragraphText = t } else { paragraphText = "" }
        let parsed = MarkdownInlineParser(references: document.references).parse(paragraphText)
        #expect(parsed.plainText.contains("full"), "plain=\(parsed.plainText)")
    }
}

struct BugProbeFrontmatterTests {

    @Test func frontmatterBodyExcludesHeader() {
        let text = "---\ntags: [a, b]\ntitle: T\n---\n\nbody\n"
        let document = MarkdownBlockParser.parseDocument(text)
        #expect(document.frontmatter?.fields.count == 2, "fields=\(document.frontmatter?.fields ?? [])")
        #expect(document.blocks.count == 1, "blocks=\(document.blocks)")
    }

    @Test func frontmatterWithoutClosingDelimiter() {
        let text = "---\ntitle: T\n\nbody\n"
        let document = MarkdownBlockParser.parseDocument(text)
        #expect(document.frontmatter == nil, "frontmatter=\(String(describing: document.frontmatter))")
    }

    @Test func horizontalRuleIsNotFrontmatter() {
        let text = "---\n\nbody\n"
        let document = MarkdownBlockParser.parseDocument(text)
        #expect(document.frontmatter == nil, "frontmatter=\(String(describing: document.frontmatter))")
        // `---` here is a thematic break; `body` is a separate paragraph.
        #expect(document.blocks.count == 2, "blocks=\(document.blocks)")
    }
}
