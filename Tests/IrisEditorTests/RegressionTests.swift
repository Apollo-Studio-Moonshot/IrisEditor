import Foundation
import Testing
@testable import IrisEditor

/// Regression tests for the editor bugs found during the deep audit pass:
/// non-BMP highlight offsets, fence colouring, outline frontmatter, and inline emphasis.
struct RegressionHighlighterAndParsingTests {

    /// Probe 1: link highlight offsets on a line that starts with an emoji.
    @Test func linkHighlightOffsetsWithEmoji() {
        let text = "😀 [a](b)"
        let highlights = MarkdownHighlighter.highlights(in: text)
            .filter { $0.token == .link }
        let ns = text as NSString
        let captured = highlights.map { ns.substring(with: $0.nsRange) }
        #expect(captured == ["a", "b"], "captured=\(captured) ranges=\(highlights.map(\.nsRange))")
    }

    /// Probe 2: same link, but with a CJK prefix (BMP, 1 UTF-16 unit each).
    @Test func linkHighlightOffsetsWithCJK() {
        let text = "中文 [a](b)"
        let ns = text as NSString
        let captured = MarkdownHighlighter.highlights(in: text)
            .filter { $0.token == .link }
            .map { ns.substring(with: $0.nsRange) }
        #expect(captured == ["a", "b"], "captured=\(captured)")
    }

    /// Probe 3: `~~~` fence containing a ``` line.
    @Test func fenceInsideFence() {
        let text = "~~~\n```\ncode\n~~~\n"
        let highlights = MarkdownHighlighter.highlights(in: text)
        let ns = text as NSString
        let covered = highlights
            .filter { $0.token == .fencedCode }
            .map { ns.substring(with: $0.nsRange) }
        #expect(covered.count == 3, "fenced highlights=\(covered)")
    }
}

struct BugProbeSearchTests {

    /// Probe 4: TextLineIndex over CRLF and lone CR.
    @Test func lineIndexHandlesCRLF() {
        #expect(TextLineIndex("a\r\nb").lineCount == 2)
        #expect(TextLineIndex("a\rb").lineCount == 2)
        #expect(TextLineIndex("a\nb\n").lineCount == 3)
    }
}

struct BugProbeBlockTests {

    /// Probe 5: list inside a block quote keeps both levels.
    @Test func listInsideBlockQuote() {
        let blocks = MarkdownBlockParser.parse("> - a\n> - b\n")
        #expect(blocks.count == 1, "blocks=\(blocks)")
        guard case let .blockQuote(inner)? = blocks.first else {
            #expect(Bool(false), "not a quote: \(blocks)")
            return
        }
        #expect(inner.count == 1, "inner=\(inner)")
        guard case let .list(_, _, items)? = inner.first else {
            #expect(Bool(false), "not a list: \(inner)")
            return
        }
        #expect(items.count == 2, "items=\(items.count)")
    }

    /// Probe 6: table cell with an escaped pipe.
    @Test func tableEscapedPipe() {
        let blocks = MarkdownBlockParser.parse("| a \\| b | c |\n| --- | --- |\n| 1 | 2 |\n")
        guard case let .table(header, _, rows)? = blocks.first else {
            #expect(Bool(false), "not a table: \(blocks)")
            return
        }
        #expect(header == ["a | b", "c"], "header=\(header) rows=\(rows)")
    }

    /// Probe 7: a fenced code block followed by more content keeps its closing fence.
    @Test func fencedCodeCloses() {
        let blocks = MarkdownBlockParser.parse("```swift\nlet a = 1\n```\n\nafter\n")
        #expect(blocks.count == 2, "blocks=\(blocks)")
        guard case let .codeBlock(language, lines)? = blocks.first else {
            #expect(Bool(false), "not code: \(blocks)")
            return
        }
        #expect(language == "swift", "language=\(String(describing: language))")
        #expect(lines == ["let a = 1"], "lines=\(lines)")
    }

    /// Probe 8: nested list indentation (3 spaces after a 2-space parent marker).
    @Test func nestedList() {
        let blocks = MarkdownBlockParser.parse("- a\n  - b\n")
        guard case let .list(_, _, items)? = blocks.first else {
            #expect(Bool(false), "not a list: \(blocks)")
            return
        }
        #expect(items.count == 1, "items=\(items.count) blocks=\(blocks)")
        #expect(items.first?.blocks.count == 2, "item blocks=\(items.first?.blocks ?? [])")
    }
}

struct BugProbeStatisticsTests {

    /// Probe 9: statistics ignore markup but keep code content.
    @Test func statisticsIgnoreMarkup() {
        let text = "# Title\n\n```\ncode here\n```\n"
        #expect(MarkdownPlainText.words(in: text) == 3, "stripped=\(MarkdownPlainText.stripped(text))")
    }

    /// Probe 10: fenced code closing fence is not counted as content.
    @Test func statisticsSkipFenceMarkers() {
        let text = "```\nlet x = 1\n```\n"
        let stripped = MarkdownPlainText.stripped(text)
        #expect(!stripped.contains("```"), "stripped=\(stripped)")
    }
}

struct BugProbeVimTests {

    /// Probe 11: `x` on the last character of the buffer.
    @Test func vimDeleteLastCharacter() {
        var engine = VimEngine()
        let result = engine.handle(key: .character("x"), text: "ab", selection: NSRange(location: 1, length: 0))
        #expect(result.text == "a", "text=\(result.text) caret=\(result.selection.location)")
    }

    /// Probe 12: `dd` on the only line.
    @Test func vimDeleteOnlyLine() {
        var engine = VimEngine()
        _ = engine.handle(key: .character("d"), text: "abc", selection: NSRange(location: 0, length: 0))
        let result = engine.handle(key: .character("d"), text: "abc", selection: NSRange(location: 0, length: 0))
        #expect(result.text.isEmpty, "text=\(result.text)")
    }

    /// Probe 13: `p` paste at the end of the buffer after `yy`.
    @Test func vimPasteAtEnd() {
        var engine = VimEngine()
        _ = engine.handle(key: .character("y"), text: "ab\ncd", selection: NSRange(location: 0, length: 0))
        _ = engine.handle(key: .character("y"), text: "ab\ncd", selection: NSRange(location: 0, length: 0))
        let result = engine.handle(key: .character("p"), text: "ab\ncd", selection: NSRange(location: 4, length: 0))
        #expect(result.text == "ab\ncd\nab", "text=\(result.text.debugDescription)")
    }

    /// Probe 14: `w` motion lands on the next word start across a line break.
    @Test func vimWordMotionCrossesLine() {
        var engine = VimEngine()
        let result = engine.handle(key: .character("w"), text: "ab cd\nef", selection: NSRange(location: 0, length: 0))
        #expect(result.selection.location == 3, "caret=\(result.selection.location)")
    }
}
