import Foundation
import Testing
@testable import IrisEditor

/// Regression tests for the Vim engine state machine: counts, linewise operators, and motions.
struct RegressionVimEngineTests {

    private func run(_ keys: [String], text: String, caret: Int) -> VimResult {
        var engine = VimEngine()
        var current = VimResult(text: text, selection: NSRange(location: caret, length: 0), mode: .normal)
        for key in keys {
            current = engine.handle(
                key: .character(Character(key)),
                text: current.text,
                selection: current.selection
            )
        }
        return current
    }

    @Test func dwAtEndOfLine() {
        let result = run(["d", "w"], text: "ab cd", caret: 3)
        #expect(result.text == "ab ", "text=\(result.text.debugDescription)")
    }

    @Test func dwAcrossLastWord() {
        let result = run(["d", "w"], text: "ab cd", caret: 0)
        #expect(result.text == "cd", "text=\(result.text.debugDescription)")
    }

    @Test func djDeletesTwoLines() {
        let result = run(["d", "j"], text: "a\nb\nc", caret: 0)
        #expect(result.text == "c", "text=\(result.text.debugDescription)")
    }

    @Test func cwChangesWord() {
        let result = run(["c", "w"], text: "ab cd", caret: 0)
        #expect(result.text == " cd", "text=\(result.text.debugDescription) mode=\(result.mode)")
        #expect(result.mode == .insert, "mode=\(result.mode)")
    }

    @Test func yyThenPasteBelowMiddleLine() {
        let result = run(["y", "y", "p"], text: "a\nb\nc", caret: 0)
        #expect(result.text == "a\na\nb\nc", "text=\(result.text.debugDescription)")
    }

    @Test func yyThenPasteAboveLastLine() {
        let result = run(["y", "y", "P"], text: "a\nb", caret: 1)
        #expect(result.text == "a\na\nb", "text=\(result.text.debugDescription)")
    }

    @Test func ddPasteRestoresLine() {
        let result = run(["d", "d", "p"], text: "a\nb\nc", caret: 2)
        // dd yanks line 2, the caret lands on line 2 ("c"), and p pastes below it.
        #expect(result.text == "a\nc\nb", "text=\(result.text.debugDescription)")
    }

    @Test func xAtEndOfLineDoesNotJoin() {
        let result = run(["x"], text: "ab\ncd", caret: 1)
        #expect(result.text == "a\ncd", "text=\(result.text.debugDescription)")
    }

    @Test func GGoesToLastLine() {
        let result = run(["G"], text: "a\nbb\nc", caret: 0)
        #expect(result.selection.location == 5, "caret=\(result.selection.location)")
    }

    @Test func dollarMotionAtEmptyLastLine() {
        let result = run(["$"], text: "a\n", caret: 0)
        // `$` parks on the last character (`a`), never on the newline.
        #expect(result.selection.location == 0, "caret=\(result.selection.location)")
    }

    @Test func countDeleteTwoWords() {
        let result = run(["2", "d", "w"], text: "a b c", caret: 0)
        #expect(result.text == "c", "text=\(result.text.debugDescription)")
    }

    @Test func undoAfterDelete() {
        var engine = VimEngine()
        let del = engine.handle(key: .character("d"), text: "abc", selection: NSRange(location: 0, length: 0))
        let del2 = engine.handle(key: .character("d"), text: del.text, selection: del.selection)
        let undo = engine.handle(key: .character("u"), text: del2.text, selection: del2.selection)
        #expect(undo.text.contains("abc") || undo.command == .undo, "text=\(undo.text.debugDescription) cmd=\(undo.command)")
    }

    @Test func visualModeSelectionIsInclusive() {
        var engine = VimEngine()
        var state = engine.handle(key: .character("v"), text: "abcdef", selection: NSRange(location: 1, length: 0))
        state = engine.handle(key: .character("l"), text: state.text, selection: state.selection)
        #expect(state.mode == .visual, "mode=\(state.mode)")
        #expect(state.selection.length == 2, "selection=\(state.selection)")
    }

    @Test func escapeFromInsertMovesLeft() {
        var engine = VimEngine()
        let result = engine.exitInsertMode(text: "abc", selection: NSRange(location: 3, length: 0))
        #expect(result.mode == .normal, "mode=\(result.mode)")
        #expect(result.selection.location == 2, "caret=\(result.selection.location)")
    }

    @Test func escapeInInsertAtStartStays() {
        var engine = VimEngine()
        let result = engine.exitInsertMode(text: "abc", selection: NSRange(location: 0, length: 0))
        #expect(result.selection.location == 0, "caret=\(result.selection.location)")
    }
}
