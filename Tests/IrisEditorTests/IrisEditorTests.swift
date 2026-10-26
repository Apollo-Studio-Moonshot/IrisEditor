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
            case .unorderedList: return "ul"
            case .orderedList: return "ol"
            case .table: return "table"
            case .thematicBreak: return "hr"
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
