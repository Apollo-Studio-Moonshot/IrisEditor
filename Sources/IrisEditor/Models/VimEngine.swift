import Foundation

/// Modal state for the Vim editing mode.
enum VimMode: String, Equatable, Sendable {
    case normal
    case insert
    case visual
    case visualLine
    case command

    var label: String {
        switch self {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .visualLine: return "VISUAL LINE"
        case .command: return "COMMAND"
        }
    }
}

/// Keys that reach the modal engine. Everything else is ordinary text input and is
/// forwarded to `NSTextView`.
enum VimKey: Equatable, Sendable {
    case character(Character)
    case escape
    case returnKey
    case backspace
    case controlR
}

/// A pure description of what the text view should do after a modal key press.
struct VimResult: Equatable, Sendable {
    enum Command: Equatable, Sendable {
        case none
        case save
        case closeTab
        case saveAndClose
        case undo
        case redo
        case openFind
    }

    var handled: Bool = true
    var text: String
    var selection: NSRange
    var mode: VimMode
    var command: Command = .none
}

/// A small, dependency-free Vim emulation layer.
///
/// The engine owns no AppKit state: it receives the current text and selection and
/// returns the text and selection that should follow. That keeps the tricky range
/// math unit-testable and lets `IrisTextView` apply edits through its normal undo
/// stack. Supported Normal/Visual commands include counts, `h j k l w b e 0 $ gg G`,
/// `i a I A o O`, `x`, `dd`/`cc`/`yy`, `d`/`c`/`y` motions, `p`/`P`, `u`, `Ctrl-R`,
/// `v`/`V`, and `:w`, `:q`, `:wq`, and `:<line>`.
struct VimEngine {
    private(set) var mode: VimMode = .normal

    private var countBuffer = ""
    private var pendingOperator: Character?
    private var pendingG = false
    private var register = ""
    private var registerIsLinewise = false
    private var commandBuffer = ""
    private var visualAnchor = 0
    private var visualCursor = 0
    private var lastStatus: String?

    var statusText: String {
        if let lastStatus { return lastStatus }
        if mode == .command { return ":" + commandBuffer }
        return mode.label
    }

    mutating func reset() {
        mode = .normal
        countBuffer = ""
        pendingOperator = nil
        pendingG = false
        commandBuffer = ""
        lastStatus = nil
    }

    /// Leaves Insert mode after Escape and nudges the caret one character left,
    /// matching Vim.
    mutating func exitInsertMode(text: String, selection: NSRange) -> VimResult {
        let ns = text as NSString
        let caret = min(max(0, selection.location), ns.length)
        let adjusted = caret > 0 ? caret - 1 : 0
        return finish(
            text: text,
            selection: NSRange(location: adjusted, length: 0),
            mode: .normal
        )
    }

    mutating func handle(key: VimKey, text: String, selection: NSRange) -> VimResult {
        lastStatus = nil
        if mode == .command {
            return handleCommandKey(key, text: text, selection: selection)
        }

        if pendingG {
            pendingG = false
            if case .character(let character) = key, character == "g" {
                let ns = text as NSString
                if mode == .visual || mode == .visualLine {
                    visualCursor = 0
                    return finish(
                        text: text,
                        selection: visualSelection(
                            anchor: visualAnchor,
                            cursor: 0,
                            text: ns,
                            linewise: mode == .visualLine
                        ).range,
                        mode: mode
                    )
                }
                return finish(text: text, selection: NSRange(location: 0, length: 0), mode: .normal)
            }
            lastStatus = "NORMAL"
            return finish(text: text, selection: Normalize.selection(selection, in: text), mode: mode)
        }

        switch key {
        case .escape:
            pendingOperator = nil
            countBuffer = ""
            if mode == .visual || mode == .visualLine {
                let caret = min(selection.location, (text as NSString).length)
                return finish(text: text, selection: NSRange(location: caret, length: 0), mode: .normal)
            }
            return finish(text: text, selection: Normalize.selection(selection, in: text), mode: .normal)

        case .returnKey:
            return finish(text: text, selection: Normalize.selection(selection, in: text), mode: mode)

        case .backspace, .controlR:
            if case .controlR = key, mode == .normal {
                return finish(
                    text: text,
                    selection: Normalize.selection(selection, in: text),
                    mode: mode,
                    command: .redo
                )
            }
            return finish(text: text, selection: Normalize.selection(selection, in: text), mode: mode)

        case .character(let character):
            return handleCharacter(
                character,
                text: text,
                selection: Normalize.selection(selection, in: text)
            )
        }
    }

    // MARK: - Key handling

    private mutating func handleCharacter(
        _ character: Character,
        text: String,
        selection: NSRange
    ) -> VimResult {
        let ns = text as NSString
        let count = countBuffer.isEmpty ? 1 : max(1, Int(countBuffer) ?? 1)

        if pendingOperator != nil {
            // A count after the operator (`d2w`) extends the motion count.
            if character.isNumber {
                countBuffer.append(character)
                return finish(text: text, selection: selection, mode: mode)
            }
            return handlePendingOperator(character, count: count, text: text, ns: ns, caret: selection.location)
        }

        if character.isNumber, character != "0" || !countBuffer.isEmpty {
            if character.isNumber {
                countBuffer.append(character)
                return finish(text: text, selection: selection, mode: mode)
            }
        }

        if mode == .visual || mode == .visualLine {
            return handleVisualKey(character, count: count, text: text, selection: selection)
        }

        switch character {
        case "h", "j", "k", "l", "w", "b", "e", "0", "$":
            countBuffer = ""
            let target = move(character, from: selection.location, count: count, in: ns)
            return finish(text: text, selection: NSRange(location: target, length: 0), mode: .normal)

        case "g":
            countBuffer = ""
            pendingG = true
            return finish(text: text, selection: selection, mode: .normal)

        case "G":
            countBuffer = ""
            let target = documentEnd(in: ns)
            return finish(text: text, selection: NSRange(location: target, length: 0), mode: .normal)

        case "i":
            countBuffer = ""
            return enterInsert(at: selection.location, text: text)
        case "a":
            countBuffer = ""
            let target = min(selection.location + 1, ns.length)
            return enterInsert(at: target, text: text)
        case "I":
            countBuffer = ""
            return enterInsert(at: lineStart(selection.location, in: ns), text: text)
        case "A":
            countBuffer = ""
            return enterInsert(at: lineContentEnd(selection.location, in: ns), text: text)
        case "o":
            countBuffer = ""
            let line = lineRange(selection.location, in: ns)
            let insertAt = NSMaxRange(line)
            // Appending after the final line needs the caret after the new newline;
            // otherwise the inserted newline is the new blank line's terminator and the
            // caret belongs at its start.
            let caret = insertAt == ns.length && !text.hasSuffix("\n")
                ? insertAt + 1
                : insertAt
            return edit(
                range: NSRange(location: insertAt, length: 0),
                replacement: "\n",
                text: text,
                mode: .insert,
                selectionAfter: caret
            )
        case "O":
            countBuffer = ""
            let start = lineStart(selection.location, in: ns)
            return edit(
                range: NSRange(location: start, length: 0),
                replacement: "\n",
                text: text,
                mode: .insert,
                selectionAfter: start
            )

        case "x":
            countBuffer = ""
            return deleteCharacters(count: count, text: text, selection: selection)
        case "X":
            countBuffer = ""
            let start = max(0, selection.location - count)
            let range = NSRange(location: start, length: selection.location - start)
            return delete(range: range, text: text, linewise: false)
        case "D":
            countBuffer = ""
            let end = lineContentEnd(selection.location, in: ns)
            let range = NSRange(location: selection.location, length: max(0, end - selection.location))
            return delete(range: range, text: text, linewise: false)
        case "C":
            countBuffer = ""
            let end = lineContentEnd(selection.location, in: ns)
            let range = NSRange(location: selection.location, length: max(0, end - selection.location))
            return change(range: range, text: text, linewise: false)

        case "p", "P":
            countBuffer = ""
            return paste(character == "p", count: count, text: text, selection: selection)

        case "u":
            countBuffer = ""
            return finish(text: text, selection: selection, mode: .normal, command: .undo)

        case "v":
            countBuffer = ""
            visualAnchor = selection.location
            visualCursor = selection.location
            return finish(
                text: text,
                selection: NSRange(location: selection.location, length: min(1, ns.length - min(selection.location, ns.length))),
                mode: .visual
            )

        case "V":
            countBuffer = ""
            let line = lineRange(selection.location, in: ns)
            visualAnchor = line.location
            visualCursor = line.location
            return finish(text: text, selection: line, mode: .visualLine)

        case ":":
            countBuffer = ""
            commandBuffer = ""
            return finish(text: text, selection: selection, mode: .command)

        case "/":
            countBuffer = ""
            return finish(text: text, selection: selection, mode: .normal, command: .openFind)

        case "d", "c", "y":
            // Keep a leading count so `3dd` acts on three lines.
            pendingOperator = character
            return finish(text: text, selection: selection, mode: .normal)

        default:
            countBuffer = ""
            return finish(text: text, selection: selection, mode: mode)
        }
    }

    private mutating func handleVisualKey(
        _ character: Character,
        count: Int,
        text: String,
        selection: NSRange
    ) -> VimResult {
        let ns = text as NSString
        switch character {
        case "h", "j", "k", "l", "w", "b", "e", "0", "$":
            let target = move(character, from: visualCursor, count: count, in: ns)
            visualCursor = target
            let selected = visualSelection(anchor: visualAnchor, cursor: target, text: ns, linewise: mode == .visualLine)
            return finish(text: text, selection: selected.range, mode: mode)

        case "g":
            pendingG = true
            return finish(text: text, selection: selection, mode: mode)

        case "G":
            let target = documentEnd(in: ns)
            visualCursor = target
            let selected = visualSelection(anchor: visualAnchor, cursor: target, text: ns, linewise: mode == .visualLine)
            return finish(text: text, selection: selected.range, mode: mode)

        case "d", "x":
            let range = effectiveVisualRange(selection, text: ns)
            return delete(range: range, text: text, linewise: mode == .visualLine)
        case "y":
            let range = effectiveVisualRange(selection, text: ns)
            register = ns.substring(with: range)
            registerIsLinewise = mode == .visualLine
            return finish(text: text, selection: NSRange(location: range.location, length: 0), mode: .normal)
        case "c":
            let range = effectiveVisualRange(selection, text: ns)
            return change(range: range, text: text, linewise: mode == .visualLine)
        case "v", "V":
            return finish(text: text, selection: selection, mode: .normal)
        default:
            return finish(text: text, selection: selection, mode: mode)
        }
    }

    private mutating func handlePendingOperator(
        _ character: Character,
        count: Int,
        text: String,
        ns: NSString,
        caret: Int
    ) -> VimResult {
        guard let op = pendingOperator else {
            return finish(text: text, selection: NSRange(location: caret, length: 0), mode: .normal)
        }
        pendingOperator = nil
        countBuffer = ""

        if character == op {
            let line = lineRange(caret, in: ns)
            let range = repeatedLineRange(startingAt: line, count: count, in: ns)
            switch op {
            case "d": return delete(range: range, text: text, linewise: true)
            case "c": return change(range: lineContentRange(for: range, in: ns), text: text, linewise: true)
            default:
                register = ns.substring(with: range)
                registerIsLinewise = true
                return finish(text: text, selection: NSRange(location: range.location, length: 0), mode: .normal)
            }
        }

        guard let range = operatorRange(
            motion: character,
            count: count,
            from: caret,
            in: ns
        ) else {
            return finish(text: text, selection: NSRange(location: caret, length: 0), mode: .normal)
        }

        switch op {
        case "d": return delete(range: range, text: text, linewise: false)
        case "c": return change(range: range, text: text, linewise: false)
        default:
            register = ns.substring(with: range)
            registerIsLinewise = false
            return finish(text: text, selection: NSRange(location: range.location, length: 0), mode: .normal)
        }
    }

    private mutating func handleCommandKey(_ key: VimKey, text: String, selection: NSRange) -> VimResult {
        switch key {
        case .escape:
            mode = .normal
            commandBuffer = ""
            return VimResult(text: text, selection: selection, mode: .normal)
        case .backspace:
            if !commandBuffer.isEmpty { commandBuffer.removeLast() }
            return VimResult(text: text, selection: selection, mode: .command)
        case .returnKey:
            let command = commandBuffer.trimmingCharacters(in: .whitespaces)
            mode = .normal
            commandBuffer = ""
            if let line = Int(command) {
                let target = indexForLine(line, in: text as NSString)
                return VimResult(
                    text: text,
                    selection: NSRange(location: target, length: 0),
                    mode: .normal
                )
            }
            switch command {
            case "w", "write":
                return VimResult(text: text, selection: selection, mode: .normal, command: .save)
            case "q", "quit", "q!":
                return VimResult(text: text, selection: selection, mode: .normal, command: .closeTab)
            case "wq", "x":
                return VimResult(text: text, selection: selection, mode: .normal, command: .saveAndClose)
            default:
                return VimResult(text: text, selection: selection, mode: .normal, command: .none)
            }
        case .character(let character):
            guard !character.isNewline else { return VimResult(text: text, selection: selection, mode: .command) }
            commandBuffer.append(character)
            return VimResult(text: text, selection: selection, mode: .command)
        case .controlR:
            return VimResult(text: text, selection: selection, mode: .command)
        }
    }

    // MARK: - Motions

    private func move(_ character: Character, from index: Int, count: Int, in ns: NSString) -> Int {
        let clamped = min(max(0, index), ns.length)
        switch character {
        case "h":
            return max(0, clamped - count)
        case "l":
            return min(max(0, ns.length - 1), clamped + count)
        case "j":
            return vertical(clamped, delta: count, in: ns)
        case "k":
            return vertical(clamped, delta: -count, in: ns)
        case "w":
            var target = clamped
            for _ in 0..<count { target = wordForward(target, in: ns) }
            return target
        case "b":
            var target = clamped
            for _ in 0..<count { target = wordBackward(target, in: ns) }
            return target
        case "e":
            var target = clamped
            for _ in 0..<count { target = wordEnd(target, in: ns) }
            return target
        case "0":
            return lineStart(clamped, in: ns)
        case "$":
            return lineContentEnd(clamped, in: ns)
        default:
            return clamped
        }
    }

    private func operatorRange(
        motion: Character,
        count: Int,
        from index: Int,
        in ns: NSString
    ) -> NSRange? {
        switch motion {
        case "w":
            let end = move("w", from: index, count: count, in: ns)
            return range(from: index, to: end)
        case "e":
            let end = min(ns.length, move("e", from: index, count: count, in: ns) + 1)
            return range(from: index, to: end)
        case "b":
            let start = move("b", from: index, count: count, in: ns)
            return range(from: start, to: index)
        case "0":
            return range(from: lineStart(index, in: ns), to: index)
        case "$":
            return range(from: index, to: lineContentEnd(index, in: ns))
        case "j":
            let line = lineRange(index, in: ns)
            let endLine = repeatedLineRange(startingAt: line, count: count + 1, in: ns)
            return NSRange(location: line.location, length: NSMaxRange(endLine) - line.location)
        case "k":
            let current = lineRange(index, in: ns)
            var start = current.location
            for _ in 0..<count where start > 0 {
                start = lineRange(start - 1, in: ns).location
            }
            return range(from: start, to: lineContentEnd(index, in: ns))
        case "G":
            return range(from: index, to: ns.length)
        case "g":
            return range(from: 0, to: index)
        default:
            return nil
        }
    }

    private func vertical(_ index: Int, delta: Int, in ns: NSString) -> Int {
        let current = lineRange(index, in: ns)
        let column = index - current.location
        var targetLine = current
        var remaining = abs(delta)
        while remaining > 0 {
            if delta > 0 {
                let next = NSMaxRange(targetLine)
                guard next > targetLine.location, next <= ns.length else { break }
                targetLine = lineRange(next, in: ns)
            } else {
                guard targetLine.location > 0 else { break }
                targetLine = lineRange(targetLine.location - 1, in: ns)
            }
            remaining -= 1
        }
        return min(targetLine.location + column, lineContentEnd(targetLine.location, in: ns))
    }

    private func wordForward(_ index: Int, in ns: NSString) -> Int {
        var position = min(index, ns.length)

        if position < ns.length, !isWhitespace(at: position, in: ns) {
            if isCJKWord(at: position, in: ns) {
                // Each CJK character is its own word.
                position = nextCharacterIndex(after: position, in: ns)
            } else {
                while position < ns.length,
                      !isWhitespace(at: position, in: ns),
                      !isCJKWord(at: position, in: ns) {
                    position = nextCharacterIndex(after: position, in: ns)
                }
            }
        }

        while position < ns.length, isWhitespace(at: position, in: ns) {
            position = nextCharacterIndex(after: position, in: ns)
        }
        return position
    }

    private func wordBackward(_ index: Int, in ns: NSString) -> Int {
        var position = min(index, ns.length)
        if position > 0 { position = previousCharacterIndex(before: position, in: ns) }

        while position > 0, isWhitespace(at: position, in: ns) {
            position = previousCharacterIndex(before: position, in: ns)
        }

        if isCJKWord(at: position, in: ns) { return position }

        while position > 0 {
            let previous = previousCharacterIndex(before: position, in: ns)
            if isWhitespace(at: previous, in: ns) || isCJKWord(at: previous, in: ns) {
                break
            }
            position = previous
        }
        return position
    }

    private func wordEnd(_ index: Int, in ns: NSString) -> Int {
        var position = min(index, ns.length)

        if position < ns.length, !isWhitespace(at: position, in: ns) {
            if isCJKWord(at: position, in: ns) {
                return position
            }
            position = nextCharacterIndex(after: position, in: ns)
        }

        while position < ns.length, isWhitespace(at: position, in: ns) {
            position = nextCharacterIndex(after: position, in: ns)
        }

        if position < ns.length, isCJKWord(at: position, in: ns) {
            return position
        }

        while position < ns.length,
              !isWhitespace(at: position, in: ns),
              !isCJKWord(at: position, in: ns) {
            position = nextCharacterIndex(after: position, in: ns)
        }

        return position > 0 ? previousCharacterIndex(before: position, in: ns) : 0
    }

    private func isWhitespace(at index: Int, in ns: NSString) -> Bool {
        guard index >= 0, index < ns.length else { return false }
        return isWhitespace(ns.character(at: index))
    }

    /// True when the composed character at `index` is a CJK ideograph or kana syllable.
    private func isCJKWord(at index: Int, in ns: NSString) -> Bool {
        guard index >= 0, index < ns.length else { return false }
        let range = ns.rangeOfComposedCharacterSequence(at: index)
        return ns.substring(with: range).unicodeScalars.contains { CJKText.isWordScalar($0) }
    }

    /// Steps over a full composed character so surrogate pairs are never split.
    private func nextCharacterIndex(after index: Int, in ns: NSString) -> Int {
        guard index < ns.length else { return ns.length }
        return min(ns.length, NSMaxRange(ns.rangeOfComposedCharacterSequence(at: index)))
    }

    private func previousCharacterIndex(before index: Int, in ns: NSString) -> Int {
        guard index > 0 else { return 0 }
        return ns.rangeOfComposedCharacterSequence(at: index - 1).location
    }

    // MARK: - Edits

    private mutating func enterInsert(at location: Int, text: String) -> VimResult {
        let ns = text as NSString
        let target = min(max(0, location), ns.length)
        mode = .insert
        return VimResult(
            text: text,
            selection: NSRange(location: target, length: 0),
            mode: .insert
        )
    }

    private mutating func edit(
        range: NSRange,
        replacement: String,
        text: String,
        mode: VimMode,
        selectionAfter: Int
    ) -> VimResult {
        let ns = text as NSString
        let safe = clampedRange(range, in: ns)
        let updated = ns.replacingCharacters(in: safe, with: replacement)
        self.mode = mode
        let target = min(max(0, selectionAfter), (updated as NSString).length)
        return VimResult(
            text: updated,
            selection: NSRange(location: target, length: 0),
            mode: mode
        )
    }

    private mutating func deleteCharacters(count: Int, text: String, selection: NSRange) -> VimResult {
        let ns = text as NSString
        let start = min(selection.location, ns.length)
        // `x` stops at the end of the line rather than joining the next line.
        let end = min(lineContentEnd(start, in: ns), start + count)
        let range = NSRange(location: start, length: max(0, end - start))
        return delete(range: range, text: text, linewise: false)
    }

    private mutating func delete(range: NSRange, text: String, linewise: Bool) -> VimResult {
        let ns = text as NSString
        let safe = clampedRange(range, in: ns)
        guard safe.length > 0 else {
            return finish(text: text, selection: NSRange(location: safe.location, length: 0), mode: .normal)
        }
        register = ns.substring(with: safe)
        registerIsLinewise = linewise
        let updated = ns.replacingCharacters(in: safe, with: "")
        let caret = min(safe.location, (updated as NSString).length)
        return finish(text: updated, selection: NSRange(location: caret, length: 0), mode: .normal)
    }

    private mutating func change(range: NSRange, text: String, linewise: Bool) -> VimResult {
        let ns = text as NSString
        let safe = clampedRange(range, in: ns)
        register = ns.substring(with: safe)
        registerIsLinewise = linewise
        let updated = ns.replacingCharacters(in: safe, with: "")
        mode = .insert
        return VimResult(
            text: updated,
            selection: NSRange(location: safe.location, length: 0),
            mode: .insert
        )
    }

    private mutating func paste(_ after: Bool, count: Int, text: String, selection: NSRange) -> VimResult {
        guard !register.isEmpty else {
            return finish(text: text, selection: selection, mode: .normal)
        }
        let ns = text as NSString
        let payload = String(repeating: register, count: max(1, count))
        let location: Int
        if registerIsLinewise {
            if after {
                location = NSMaxRange(lineRange(selection.location, in: ns))
            } else {
                location = lineStart(selection.location, in: ns)
            }
        } else {
            location = after ? min(selection.location + 1, ns.length) : min(selection.location, ns.length)
        }
        let updated = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: payload)
        let caret = location + max(0, (payload as NSString).length - 1)
        return finish(
            text: updated,
            selection: NSRange(location: min(caret, (updated as NSString).length), length: 0),
            mode: .normal
        )
    }

    // MARK: - Helpers

    private mutating func finish(
        text: String,
        selection: NSRange,
        mode: VimMode,
        command: VimResult.Command = .none
    ) -> VimResult {
        self.mode = mode
        return VimResult(
            text: text,
            selection: Normalize.selection(selection, in: text),
            mode: mode,
            command: command
        )
    }

    private func visualSelection(
        anchor: Int,
        cursor: Int,
        text: NSString,
        linewise: Bool
    ) -> (range: NSRange, cursor: Int) {
        if linewise {
            let first = lineRange(anchor, in: text)
            let second = lineRange(cursor, in: text)
            let start = min(first.location, second.location)
            let end = max(NSMaxRange(first), NSMaxRange(second))
            return (NSRange(location: start, length: end - start), cursor)
        }
        let lower = min(anchor, cursor)
        let upper = max(anchor, cursor)
        return (NSRange(location: lower, length: upper - lower + 1), cursor)
    }

    private func effectiveVisualRange(_ selection: NSRange, text: NSString) -> NSRange {
        if selection.length > 0 { return clampedRange(selection, in: text) }
        let safe = min(selection.location, text.length)
        return NSRange(location: safe, length: min(1, text.length - safe))
    }

    private func range(from start: Int, to end: Int) -> NSRange {
        let lower = min(start, end)
        let upper = max(start, end)
        return NSRange(location: lower, length: upper - lower)
    }

    private func lineRange(_ index: Int, in ns: NSString) -> NSRange {
        let clamped = min(max(0, index), ns.length)
        return ns.lineRange(for: NSRange(location: clamped, length: 0))
    }

    private func lineStart(_ index: Int, in ns: NSString) -> Int {
        lineRange(index, in: ns).location
    }

    private func lineContentEnd(_ index: Int, in ns: NSString) -> Int {
        let range = lineRange(index, in: ns)
        var end = NSMaxRange(range)
        while end > range.location {
            let character = ns.character(at: end - 1)
            if character == 10 || character == 13 {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private func lineContentRange(for range: NSRange, in ns: NSString) -> NSRange {
        var end = NSMaxRange(range)
        while end > range.location, end <= ns.length {
            let character = ns.character(at: end - 1)
            if character == 10 || character == 13 { end -= 1 } else { break }
        }
        return NSRange(location: range.location, length: end - range.location)
    }

    private func repeatedLineRange(startingAt first: NSRange, count: Int, in ns: NSString) -> NSRange {
        var end = NSMaxRange(first)
        var remaining = max(1, count) - 1
        while remaining > 0, end < ns.length {
            let next = lineRange(end, in: ns)
            guard next.length > 0 || next.location < ns.length else { break }
            end = NSMaxRange(next)
            remaining -= 1
        }
        var start = first.location
        // Deleting the final line should also consume the newline before it so the
        // document does not end with a stray blank line.
        if end >= ns.length, start > 0 {
            start -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    private func documentEnd(in ns: NSString) -> Int {
        guard ns.length > 0 else { return 0 }
        return lineRange(ns.length - 1, in: ns).location
    }

    private func indexForLine(_ line: Int, in ns: NSString) -> Int {
        guard line > 1 else { return 0 }
        var current = 1
        var index = 0
        while index < ns.length, current < line {
            let range = ns.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(range)
            guard index > range.location else { break }
            current += 1
        }
        return min(index, ns.length)
    }

    private func clampedRange(_ range: NSRange, in ns: NSString) -> NSRange {
        let location = min(max(0, range.location), ns.length)
        let length = min(max(0, range.length), ns.length - location)
        return NSRange(location: location, length: length)
    }

    private func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

/// Keeps selections inside a text after a modal edit.
private enum Normalize {
    static func selection(_ selection: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, selection.location), length)
        let safeLength = min(max(0, selection.length), length - location)
        return NSRange(location: location, length: safeLength)
    }
}
