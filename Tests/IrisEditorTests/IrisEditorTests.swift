import Foundation
import Testing
@testable import IrisEditor

struct TextSearchTests {
    @Test func findsCaseInsensitiveMatches() {
        let ranges = TextSearch.nsRanges(of: "swift", in: "Swift and swift and SWIFT")
        #expect(ranges.count == 3)
        #expect(ranges.first?.location == 0)
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
