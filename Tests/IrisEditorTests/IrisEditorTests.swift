import Foundation
import Testing
@testable import IrisEditor

struct TextSearchTests {
    @Test func findsCaseInsensitiveMatches() {
        let ranges = TextSearch.nsRanges(of: "swift", in: "Swift and swift and SWIFT")
        #expect(ranges.count == 3)
        #expect(ranges.first?.location == 0)
    }

    @Test func caseSensitiveSearchNarrowsMatches() {
        let ranges = TextSearch.nsRanges(of: "swift", in: "Swift and swift and SWIFT", caseSensitive: true)
        #expect(ranges.count == 1)
        #expect(ranges.first?.location == 10)
    }

    @Test func wholeWordSearchSkipsSubstrings() {
        let text = "cat category Cat"
        #expect(TextSearch.nsRanges(of: "cat", in: text, wholeWord: true).count == 2)
        #expect(TextSearch.nsRanges(of: "cat", in: text).count == 3)
    }

    @Test func wholeWordRespectsUnderscoreNeighbors() {
        // "cat" inside "tom_cat" is not a standalone word.
        #expect(TextSearch.nsRanges(of: "cat", in: "tom_cat cat", wholeWord: true).count == 1)
    }

    @Test func emptyQueryReturnsNoMatches() {
        #expect(TextSearch.nsRanges(of: "", in: "abc").isEmpty)
    }

    @Test func swiftRangesBridgeToNSStringOffsets() {
        let text = "alpha beta alpha"
        let ranges = TextSearch.ranges(of: "alpha", in: text)
        #expect(ranges.count == 2)
        #expect(ranges.map { text.distance(from: text.startIndex, to: $0.lowerBound) } == [0, 11])
    }
}

struct MarkdownPlainTextTests {
    @Test func stripsHeadingMarkers() {
        let result = MarkdownPlainText.stripped("# Hello")
        #expect(result == "Hello")
    }

    @Test func stripsStrongAndEmphasis() {
        let result = MarkdownPlainText.stripped("**bold** and *italic*")
        #expect(result == "bold and italic")
    }

    @Test func countsWordsWithoutMarkers() {
        #expect(MarkdownPlainText.words(in: "**bold text** here") == 3)
    }

    @Test func countsChineseCharactersAsWords() {
        #expect(MarkdownPlainText.words(in: "你好世界") == 4)
        #expect(MarkdownPlainText.words(in: "Hello 世界") == 3)
        #expect(MarkdownPlainText.words(in: "你好，世界！") == 4)
        #expect(MarkdownPlainText.words(in: "**你好** 世界") == 4)
    }

    @Test func keepsHangulWordsWhitespaceDelimited() {
        #expect(MarkdownPlainText.words(in: "안녕하세요 세계") == 2)
    }
}

struct MarkdownHighlighterTests {
    @Test func highlightsHeadings() {
        let result = MarkdownHighlighter.highlights(in: "# Title")
        #expect(result.contains { $0.token == .heading && $0.nsRange.location == 0 })
    }

    @Test func highlightsCodeFences() {
        let text = "```\nlet x = 1\n```"
        let result = MarkdownHighlighter.highlights(in: text)
        #expect(result.contains { $0.token == .fencedCode })
    }

    @Test func noHighlightsForEmptyText() {
        #expect(MarkdownHighlighter.highlights(in: "").isEmpty)
    }

    @Test func highlightsUseAbsoluteOffsetsForMultilineDocuments() {
        let text = "intro\n# Title"
        let result = MarkdownHighlighter.highlights(in: text)
        let heading = result.first { $0.token == .heading }
        #expect(heading != nil)
        #expect(heading?.nsRange.location == 6) // after "intro\n"
    }
}

struct TextLineIndexTests {
    @Test func countsLinesForLFSeparatedText() {
        let index = TextLineIndex("one\ntwo\nthree")
        #expect(index.lineCount == 3)
        #expect(index.lineNumber(atUTF16Index: 0) == 1)
        #expect(index.lineNumber(atUTF16Index: 4) == 2)
        #expect(index.lineNumber(atUTF16Index: 8) == 3)
    }

    @Test func handlesEmptyText() {
        let index = TextLineIndex("")
        #expect(index.lineCount == 1)
        #expect(index.lineNumber(atUTF16Index: 0) == 1)
        #expect(index.lineStart(forLine: 1) == 0)
    }

    @Test func handlesCRLFAndCRLineEndings() {
        let crlf = TextLineIndex("a\r\nb")
        #expect(crlf.lineCount == 2)
        #expect(crlf.lineStart(forLine: 2) == 3)

        let cr = TextLineIndex("a\rb")
        #expect(cr.lineCount == 2)
        #expect(cr.lineStart(forLine: 2) == 2)
    }

    @Test func returnsNilForOutOfRangeLines() {
        let index = TextLineIndex("single")
        #expect(index.lineStart(forLine: 0) == nil)
        #expect(index.lineStart(forLine: 2) == nil)
    }
}

@MainActor
struct EditorDocumentTests {
    @Test func reportsTextStatistics() {
        let document = EditorDocument()
        document.text = "Hello world\nSecond line"

        #expect(document.lineCount == 2)
        #expect(document.wordCount == 4)
        #expect(document.characterCount == 23)
        #expect(document.utf8ByteCount == 23)
    }

    @Test func countsCJKStatistics() {
        let document = EditorDocument()
        document.text = "# 标题\n你好世界"

        #expect(document.wordCount == 6)
        #expect(document.characterCount == 7)
    }

    @Test func untitledDocumentUsesDefaultName() {
        let document = EditorDocument()
        #expect(document.displayName == "Untitled.md")
        #expect(document.fileURL == nil)
        #expect(document.isDirty == false)
    }

    @Test func markdownAwareWordCountStripsMarkers() {
        let document = EditorDocument()
        document.text = "# Heading\n**bold** and *italic* and `code`"

        // Visible words: Heading, bold, and, italic, and, code = 6
        #expect(document.wordCount == 6)
    }

    @Test func markdownAwareCharacterCountStripsSyntax() {
        let document = EditorDocument()
        document.text = "**hi**"
        #expect(document.characterCount == 2)
    }
}

struct MarkdownFormattingTests {
    @Test func wrapsSelectionWithMarkers() {
        let text = "hello world"
        let result = MarkdownFormatting.toggle(
            text: text,
            selection: NSRange(location: 0, length: 5),
            prefix: "**"
        )
        #expect(result?.text == "**hello** world")
        #expect(result?.selection.length == (("*" as NSString).length * 4 + 5))
    }

    @Test func unwrapsAlreadyWrappedSelection() {
        let text = "**hello** world"
        let result = MarkdownFormatting.toggle(
            text: text,
            selection: NSRange(location: 0, length: 9),
            prefix: "**"
        )
        #expect(result?.text == "hello world")
    }

    @Test func emojiSelectionSurvivesRoundTrip() {
        // Regression: the old UTF-16 scalar scan crashed next to surrogate pairs
        // and produced U+FFFD when unwrapping.
        let wrapped = "**😀**"
        let unwrapped = MarkdownFormatting.toggle(
            text: wrapped,
            selection: NSRange(location: 0, length: (wrapped as NSString).length),
            prefix: "**"
        )
        #expect(unwrapped?.text == "😀")

        let rewrapped = MarkdownFormatting.toggle(
            text: "😀",
            selection: NSRange(location: 0, length: 2),
            prefix: "**"
        )
        #expect(rewrapped?.text == "**😀**")
    }

    @Test func emptySelectionExpandsToWord() {
        let text = "hi 😀 café there"
        let caret = (text as NSString).range(of: "café").location + 1
        let result = MarkdownFormatting.toggle(
            text: text,
            selection: NSRange(location: caret, length: 0),
            prefix: "**"
        )
        #expect(result?.text == "hi 😀 **café** there")
    }

    @Test func linePrefixMarkerTogglesOnLineStart() {
        // Regression: the old symmetric wrap produced "Title# " for the "# " marker.
        let wrapped = MarkdownFormatting.toggle(
            text: "Title",
            selection: NSRange(location: 0, length: 5),
            prefix: "# "
        )
        #expect(wrapped?.text == "# Title")

        let unwrapped = MarkdownFormatting.toggle(
            text: "# Title",
            selection: NSRange(location: 0, length: 2),
            prefix: "# "
        )
        #expect(unwrapped?.text == "Title")
    }

    @Test func linePrefixTogglesEachLineInMultiLineSelection() {
        let text = "alpha\nbeta\ngamma"
        let wrapped = MarkdownFormatting.toggle(
            text: text,
            selection: NSRange(location: 0, length: (text as NSString).length),
            prefix: "- "
        )
        #expect(wrapped?.text == "- alpha\n- beta\n- gamma")

        let unwrapped = MarkdownFormatting.toggle(
            text: wrapped?.text ?? "",
            selection: wrapped?.selection ?? NSRange(location: 0, length: 0),
            prefix: "- "
        )
        #expect(unwrapped?.text == text)
    }

    @Test func linePrefixSkipsBlankLines() {
        let result = MarkdownFormatting.toggle(
            text: "one\n\ntwo",
            selection: NSRange(location: 0, length: 9),
            prefix: "> "
        )
        #expect(result?.text == "> one\n\n> two")
    }

    @Test func invalidSelectionRangeReturnsNil() {
        #expect(MarkdownFormatting.toggle(
            text: "abc",
            selection: NSRange(location: 5, length: 2),
            prefix: "**"
        ) == nil)
    }
}

struct MarkdownBlockParserTests {
    private func kinds(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.map { block in
            switch block {
            case .heading: return "heading"
            case .paragraph: return "para"
            case .blockQuote: return "quote"
            case .codeBlock: return "code"
            case .list(let ordered, _, _): return ordered ? "ol" : "ul"
            case .table: return "table"
            case .thematicBreak: return "hr"
            case .htmlBlock: return "html"
            }
        }
    }

    @Test func parsesFullDocument() {
        let doc = """
        # Title

        Some **bold** text here.
        - item one
        - item two

        1. first
        2. second

        > quoted line

        ```swift
        let x = 1
        ```

        ---

        Trailing paragraph.
        """
        #expect(kinds(MarkdownBlockParser.parse(doc)) == ["heading", "para", "ul", "ol", "quote", "code", "hr", "para"])
    }

    @Test func codeBlockKeepsLanguageAndLines() {
        let blocks = MarkdownBlockParser.parse("```swift\nlet x = 1\n```")
        guard case .codeBlock(let language, let lines)? = blocks.first else {
            Issue.record("expected a code block")
            return
        }
        #expect(language == "swift")
        #expect(lines == ["let x = 1"])
    }

    @Test func unclosedFenceStillRenders() {
        let blocks = MarkdownBlockParser.parse("```\ncode")
        #expect(kinds(blocks) == ["code"])
    }

    @Test func headingRequiresSpaceAfterHashes() {
        #expect(kinds(MarkdownBlockParser.parse("##Title")) == ["para"])
        #expect(kinds(MarkdownBlockParser.parse("## Title")) == ["heading"])
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(MarkdownBlockParser.parse("").isEmpty)
    }

    @Test func crlfLineEndingsParse() {
        #expect(kinds(MarkdownBlockParser.parse("# A\r\ntext")) == ["heading", "para"])
    }

    @Test func parsesPipeTable() {
        let doc = """
        | Name | Qty |
        |:-----|----:|
        | Apple | 3 |
        | Pear | 12 |

        After table.
        """
        #expect(kinds(MarkdownBlockParser.parse(doc)) == ["table", "para"])
    }

    @Test func tableHeaderAlignmentsAndRowsParse() {
        let blocks = MarkdownBlockParser.parse("| A | B |\n|:--|:-:|\n| 1 | 2 |")
        guard case .table(let header, let alignments, let rows)? = blocks.first else {
            Issue.record("expected a table")
            return
        }
        #expect(header == ["A", "B"])
        #expect(alignments == [.left, .center])
        #expect(rows == [["1", "2"]])
    }

    @Test func tableInsideCodeFenceStaysCode() {
        let doc = "```\n| A |\n|---|\n```"
        #expect(kinds(MarkdownBlockParser.parse(doc)) == ["code"])
    }

    @Test func missingDelimiterRowIsNotATable() {
        let doc = "| A | B |\n| 1 | 2 |"
        #expect(kinds(MarkdownBlockParser.parse(doc)).contains("table") == false)
    }
}

struct MarkdownTableParserTests {
    @Test func splitsRowsStripsBarsAndUnescapesPipes() {
        let cells = MarkdownTableParser.splitRow("| left | mid \\| pipe | right |")
        #expect(cells == ["left", "mid | pipe", "right"])
    }

    @Test func delimiterDetectsAlignments() {
        #expect(MarkdownTableParser.delimiterAlignments(for: "|:---|:--:|---:|")
                == [.left, .center, .right])
        #expect(MarkdownTableParser.delimiterAlignments(for: "| a | b |") == nil)
    }

    @Test func raggedRowsPadAndTruncate() {
        let lines = ["| A | B | C |", "|---|---|---|", "| 1 |", "| x | y | z | w |"]
        guard let table = MarkdownTableParser.table(startingAt: 0, in: lines) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["1", "", ""])
        #expect(table.rows[1] == ["x", "y", "z"])
        #expect(table.nextIndex == lines.count)
    }
}

struct MarkdownBasicSyntaxBlockTests {
    @Test func setextHeadingsParse() {
        let blocks = MarkdownBlockParser.parse("Heading 1\n=========\n\nHeading 2\n---------")

        guard case .heading(let level1, let text1)? = blocks.first,
              case .heading(let level2, let text2)? = blocks.last else {
            Issue.record("expected two Setext headings")
            return
        }
        #expect(level1 == 1)
        #expect(text1 == "Heading 1")
        #expect(level2 == 2)
        #expect(text2 == "Heading 2")
    }

    @Test func atxHeadingDropsClosingHashes() {
        let blocks = MarkdownBlockParser.parse("## Title ##")
        guard case .heading(let level, let text)? = blocks.first else {
            Issue.record("expected a heading")
            return
        }
        #expect(level == 2)
        #expect(text == "Title")
    }

    @Test func nestedBlockquotesParseRecursively() {
        let blocks = MarkdownBlockParser.parse("> outer\n>\n>> inner")

        guard case .blockQuote(let inner)? = blocks.first else {
            Issue.record("expected a block quote")
            return
        }
        #expect(inner.count == 2)
        guard case .paragraph(let text)? = inner.first,
              case .blockQuote(let nested)? = inner.last,
              case .paragraph(let nestedText)? = nested.first else {
            Issue.record("expected a nested block quote")
            return
        }
        #expect(text == "outer")
        #expect(nestedText == "inner")
    }

    @Test func blockquoteContainsOtherElements() {
        let doc = """
        > #### The quarterly results look great!
        >
        > - Revenue was off the chart.
        > - Profits were higher than ever.
        >
        > *Everything* is going according to **plan**.
        """
        let blocks = MarkdownBlockParser.parse(doc)

        guard case .blockQuote(let inner)? = blocks.first else {
            Issue.record("expected a block quote")
            return
        }
        let kinds = inner.map { block -> String in
            switch block {
            case .heading: return "heading"
            case .list: return "list"
            case .paragraph: return "para"
            default: return "other"
            }
        }
        #expect(kinds == ["heading", "list", "para"])
    }

    @Test func nestedUnorderedListsParse() {
        let doc = """
        - one
          - inner a
          - inner b
        - two
        """
        let blocks = MarkdownBlockParser.parse(doc)

        guard case .list(let ordered, _, let items)? = blocks.first else {
            Issue.record("expected a list")
            return
        }
        #expect(ordered == false)
        #expect(items.count == 2)

        guard case .paragraph(let text)? = items[0].blocks.first,
              case .list(_, _, let nestedItems)? = items[0].blocks.last else {
            Issue.record("expected a nested list")
            return
        }
        #expect(text == "one")
        #expect(nestedItems.count == 2)
    }

    @Test func listItemsHoldMultipleParagraphs() {
        let doc = """
        * This is the first list item.
        * Here's the second list item.

            I need to add another paragraph.

        * And here's the third list item.
        """
        let blocks = MarkdownBlockParser.parse(doc)

        guard case .list(_, _, let items)? = blocks.first else {
            Issue.record("expected a list")
            return
        }
        #expect(items.count == 3)
        #expect(items[1].blocks.count == 2)
    }

    @Test func listItemsHoldQuotesAndCode() {
        let doc = """
        - item one

            > quoted

            ```
            let x = 1
            ```
        """
        let blocks = MarkdownBlockParser.parse(doc)

        guard case .list(_, _, let items)? = blocks.first else {
            Issue.record("expected a list")
            return
        }
        #expect(items.count == 1)
        let kinds = items[0].blocks.map { block -> String in
            switch block {
            case .paragraph: return "para"
            case .blockQuote: return "quote"
            case .codeBlock: return "code"
            default: return "other"
            }
        }
        #expect(kinds == ["para", "quote", "code"])
    }

    @Test func indentedCodeBlockParses() {
        let blocks = MarkdownBlockParser.parse("    let x = 1\n    let y = 2")

        guard case .codeBlock(let language, let lines)? = blocks.first else {
            Issue.record("expected an indented code block")
            return
        }
        #expect(language == nil)
        #expect(lines == ["let x = 1", "let y = 2"])
    }

    @Test func tildeFenceKeepsLanguage() {
        let blocks = MarkdownBlockParser.parse("~~~swift\nlet x = 1\n~~~")

        guard case .codeBlock(let language, let lines)? = blocks.first else {
            Issue.record("expected a fenced code block")
            return
        }
        #expect(language == "swift")
        #expect(lines == ["let x = 1"])
    }

    @Test func fourSpaceFenceIsIndentedCode() {
        let blocks = MarkdownBlockParser.parse("    ```\n    code\n    ```")

        guard case .codeBlock(let language, let lines)? = blocks.first else {
            Issue.record("expected an indented code block")
            return
        }
        #expect(language == nil)
        #expect(lines == ["```", "code", "```"])
    }

    @Test func referenceDefinitionIsConsumed() {
        let doc = """
        [ref]: https://example.com "Example"

        Use [ref] here.
        """
        let document = MarkdownBlockParser.parseDocument(doc)

        #expect(document.references["ref"] == MarkdownLinkReference(
            destination: "https://example.com",
            title: "Example"
        ))
        #expect(document.blocks.count == 1)
        guard case .paragraph(let text)? = document.blocks.first else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(text == "Use [ref] here.")
    }

    @Test func orderedListKeepsStartNumber() {
        let blocks = MarkdownBlockParser.parse("3. three\n4. four")

        guard case .list(let ordered, let start, let items)? = blocks.first else {
            Issue.record("expected an ordered list")
            return
        }
        #expect(ordered)
        #expect(start == 3)
        #expect(items.count == 2)
    }

    @Test func orderedListAcceptsParenthesisDelimiter() {
        let blocks = MarkdownBlockParser.parse("1) one\n2) two")

        guard case .list(let ordered, _, let items)? = blocks.first else {
            Issue.record("expected an ordered list")
            return
        }
        #expect(ordered)
        #expect(items.count == 2)
    }

    @Test func escapedNumberStartsListItem() {
        let blocks = MarkdownBlockParser.parse("- 1968\\. A great year!\n- Second")

        guard case .list(_, _, let items)? = blocks.first,
              case .paragraph(let text)? = items[0].blocks.first else {
            Issue.record("expected a list item")
            return
        }
        #expect(items.count == 2)
        #expect(text == "1968\\. A great year!")
    }

    @Test func htmlBlockParses() {
        let blocks = MarkdownBlockParser.parse("<h1>Title</h1>\n<p>Body</p>")

        guard case .htmlBlock(let lines)? = blocks.first else {
            Issue.record("expected an HTML block")
            return
        }
        #expect(lines == ["<h1>Title</h1>", "<p>Body</p>"])
    }

    @Test func paragraphPreservesHardBreakSpaces() {
        let blocks = MarkdownBlockParser.parse("first line  \nsecond")

        guard case .paragraph(let text)? = blocks.first else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(text == "first line  \nsecond")
    }

    @Test func thematicBreakVariantsParse() {
        let blocks = MarkdownBlockParser.parse("---\n\n***\n\n___")
        #expect(blocks == [.thematicBreak, .thematicBreak, .thematicBreak])
    }
}

struct MarkdownInlineParserTests {
    private let parser = MarkdownInlineParser()

    @Test func emphasisCombinationsParse() {
        #expect(parser.parse("I just love **bold text**.") == [
            .text("I just love "),
            .strong([.text("bold text")]),
            .text("."),
        ])
        #expect(parser.parse("This text is ***really important***.") == [
            .text("This text is "),
            .emphasis([.strong([.text("really important")])]),
            .text("."),
        ])
        #expect(parser.parse("This text is **_really important_**.") == [
            .text("This text is "),
            .strong([.emphasis([.text("really important")])]),
            .text("."),
        ])
        #expect(parser.parse("Love**is**bold") == [
            .text("Love"),
            .strong([.text("is")]),
            .text("bold"),
        ])
        #expect(parser.parse("This is really***very***important") == [
            .text("This is really"),
            .emphasis([.strong([.text("very")])]),
            .text("important"),
        ])
        #expect(parser.parse("A*cat*meow") == [
            .text("A"),
            .emphasis([.text("cat")]),
            .text("meow"),
        ])
        #expect(parser.parse("__bold__ and _italic_") == [
            .strong([.text("bold")]),
            .text(" and "),
            .emphasis([.text("italic")]),
        ])
    }

    @Test func intrawordUnderscoresStayLiteral() {
        #expect(parser.parse("A_cat_meow") == [.text("A_cat_meow")])
        #expect(parser.parse("Love__is__bold") == [.text("Love__is__bold")])
    }

    @Test func codeSpansSupportVariableBackticks() {
        #expect(parser.parse("`code` and ``a ` b``") == [
            .code("code"),
            .text(" and "),
            .code("a ` b"),
        ])
    }

    @Test func escapesProduceLiteralCharacters() {
        #expect(parser.parse("\\*escaped\\* and 1968\\. great") == [
            .text("*escaped* and 1968. great"),
        ])
    }

    @Test func inlineLinksParseWithTitles() {
        #expect(parser.parse("[text](https://x.com \"title\")") == [
            .link(
                destination: "https://x.com",
                title: "title",
                children: [.text("text")]
            ),
        ])
    }

    @Test func referenceLinksResolve() {
        let references = [
            "ref": MarkdownLinkReference(destination: "https://example.com", title: "Example"),
            "ref2": MarkdownLinkReference(destination: "https://two.com", title: nil),
        ]
        let parser = MarkdownInlineParser(references: references)

        let expected = MarkdownInline.link(
            destination: "https://example.com",
            title: "Example",
            children: [.text("text")]
        )
        #expect(parser.parse("[text][ref]") == [expected])
        #expect(parser.parse("[ref][]") == [
            .link(
                destination: "https://example.com",
                title: "Example",
                children: [.text("ref")]
            ),
        ])
        #expect(parser.parse("[ref2]") == [
            .link(
                destination: "https://two.com",
                title: nil,
                children: [.text("ref2")]
            ),
        ])
        #expect(parser.parse("[missing]") == [.text("[missing]")])
    }

    @Test func autolinksParse() {
        #expect(parser.parse("<https://example.com>") == [
            .link(
                destination: "https://example.com",
                title: nil,
                children: [.text("https://example.com")]
            ),
        ])
        #expect(parser.parse("<user@example.com>") == [
            .link(
                destination: "mailto:user@example.com",
                title: nil,
                children: [.text("user@example.com")]
            ),
        ])
    }

    @Test func imagesAndLinkedImagesParse() {
        #expect(parser.parse("![alt](img.png \"Example\")") == [
            .image(source: "img.png", alt: "alt", title: "Example"),
        ])
        #expect(parser.parse("[![alt](img.png)](https://x.com)") == [
            .link(
                destination: "https://x.com",
                title: nil,
                children: [.image(source: "img.png", alt: "alt", title: nil)]
            ),
        ])
    }

    @Test func lineBreaksParse() {
        #expect(parser.parse("first line  \nsecond") == [
            .text("first line"),
            .hardBreak,
            .text("second"),
        ])
        #expect(parser.parse("first line\\\nsecond") == [
            .text("first line"),
            .hardBreak,
            .text("second"),
        ])
        #expect(parser.parse("first\nsecond") == [
            .text("first"),
            .softBreak,
            .text("second"),
        ])
    }

    @Test func inlineHTMLParses() {
        #expect(parser.parse("<br>") == [.hardBreak])
        #expect(parser.parse("<b>bold</b>") == [.strong([.text("bold")])])
        #expect(parser.parse("<em>word</em>") == [.emphasis([.text("word")])])
        #expect(parser.parse("<code>x</code>") == [.code("x")])
        #expect(parser.parse("<del>gone</del>") == [.strikethrough([.text("gone")])])
        #expect(parser.parse("<span>x</span>") == [
            .html("<span>"),
            .text("x"),
            .html("</span>"),
        ])
        #expect(parser.parse("This **word** is bold. This <em>word</em> is italic.") == [
            .text("This "),
            .strong([.text("word")]),
            .text(" is bold. This "),
            .emphasis([.text("word")]),
            .text(" is italic."),
        ])
    }

    @Test func strikethroughParses() {
        #expect(parser.parse("~~strike~~") == [.strikethrough([.text("strike")])])
    }

    @Test func plainTextFlattensMarkup() {
        let inlines: [MarkdownInline] = [
            .emphasis([.text("a")]),
            .softBreak,
            .text("b"),
        ]
        #expect(inlines.plainText == "a b")
    }
}

struct MarkdownHTMLTableParserTests {
    @Test func thRowBecomesHeader() {
        let html = """
        <table>
        <tr><th>A</th><th>B</th></tr>
        <tr><td>1</td><td>2</td></tr>
        </table>
        """
        guard let table = MarkdownHTMLTableParser.table(in: html) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.header == ["A", "B"])
        #expect(table.rows == [["1", "2"]])
    }

    @Test func tdOnlyTableGetsEmptyHeader() {
        let html = "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>"
        guard let table = MarkdownHTMLTableParser.table(in: html) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.header == ["", ""])
        #expect(table.rows == [["a", "b"], ["c", "d"]])
    }

    @Test func alignAttributesMapToColumnAlignment() {
        let html = "<table><tr><th align=\"right\">N</th></tr><tr><td>42</td></tr></table>"
        guard let table = MarkdownHTMLTableParser.table(in: html) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.alignments == [.right])
        #expect(table.rows == [["42"]])
    }

    @Test func cellMarkupReducesToVisibleText() {
        let html = "<table><tr><th>X</th></tr><tr><td><b>bold</b> &amp; <i>more</i></td></tr></table>"
        guard let table = MarkdownHTMLTableParser.table(in: html) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.rows == [["bold & more"]])
    }

    @Test func raggedRowsPadToColumnCount() {
        let html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td></tr></table>"
        guard let table = MarkdownHTMLTableParser.table(in: html) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.rows == [["1", ""]])
    }

    @Test func malformedMarkupIsNotATable() {
        #expect(MarkdownHTMLTableParser.table(in: "<table><tr><td>unclosed") == nil)
        #expect(MarkdownHTMLTableParser.table(in: "<h1>hi</h1>") == nil)
    }

    @Test func blockParserPromotesHTMLTables() {
        let doc = """
        <table>
        <tr><th>A</th><th>B</th></tr>
        <tr><td>1</td><td>2</td></tr>
        </table>
        """
        let blocks = MarkdownBlockParser.parse(doc)
        guard case .table(let header, _, let rows)? = blocks.first else {
            Issue.record("expected a table block")
            return
        }
        #expect(header == ["A", "B"])
        #expect(rows == [["1", "2"]])
    }

    @Test func nonTableHTMLStillParsesAsHTMLBlock() {
        let blocks = MarkdownBlockParser.parse("<h1>Title</h1>\n<p>Body</p>")
        guard case .htmlBlock(let lines)? = blocks.first else {
            Issue.record("expected an HTML block")
            return
        }
        #expect(lines == ["<h1>Title</h1>", "<p>Body</p>"])
    }
}
