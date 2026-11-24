import Foundation

/// Turns a selection into a new note and the `![[…]]` that replaces it.
enum NoteExtraction {

    /// The range to lift out of `text`.
    ///
    /// A non-empty selection is kept as the user drew it. A caret expands to the
    /// surrounding blank-line paragraph. A caret on the blank line just after a
    /// paragraph takes that paragraph.
    static func paragraphRange(in text: String, selection: NSRange) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }

        let location = min(max(0, selection.location), ns.length)
        let length = min(max(0, selection.length), ns.length - location)
        if length > 0 {
            let raw = ns.substring(with: NSRange(location: location, length: length))
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return NSRange(location: location, length: length)
            }
        }

        var line = lineBounds(in: ns, containing: min(location, max(0, ns.length - 1)))
        if isBlank(ns, line: line), line.location > 0 {
            let previous = lineBounds(in: ns, containing: line.location - 1)
            if !isBlank(ns, line: previous) {
                line = previous
            }
        }
        guard !isBlank(ns, line: line) else {
            return NSRange(location: location, length: 0)
        }

        var start = line.location
        while start > 0 {
            let previous = lineBounds(in: ns, containing: start - 1)
            if isBlank(ns, line: previous) { break }
            start = previous.location
        }

        var blockEnd = NSMaxRange(line)
        var cursor = blockEnd
        while cursor < ns.length {
            guard ns.character(at: cursor) == 10 else { break }
            let nextIndex = cursor + 1
            guard nextIndex < ns.length else { break }
            let next = lineBounds(in: ns, containing: nextIndex)
            if isBlank(ns, line: next) { break }
            blockEnd = NSMaxRange(next)
            cursor = blockEnd
        }

        return NSRange(location: start, length: blockEnd - start)
    }

    /// A short title guessed from the first line of the excerpt.
    static func suggestedTitle(from excerpt: String) -> String {
        let first = excerpt.split(whereSeparator: \.isNewline).first.map(String.init) ?? excerpt
        var title = first.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.hasPrefix("#") {
            title.removeFirst()
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = title.range(of: #"^([-*+]|\d+[.)])\s+"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        if let range = title.range(of: #"^\[[ xX]\]\s+"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "*_`"))
        if title.count > 48 {
            title = String(title.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let cleaned = fileName(from: title)
        return cleaned.isEmpty ? "Extracted Note" : cleaned
    }

    /// A single path component safe to use as a Markdown file name and a wikilink.
    static func fileName(from title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>[]#")
        let cleaned = title
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Extracted Note" : cleaned
    }

    /// Body written to the new note. An excerpt that already starts with a heading
    /// is kept as-is so the heading is not doubled.
    static func noteBody(title: String, excerpt: String) -> String {
        let body = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "# \(title)\n" }
        if body.hasPrefix("#") {
            return body.hasSuffix("\n") ? body : body + "\n"
        }
        return "# \(title)\n\n\(body)\n"
    }

    static func embed(named title: String) -> String {
        "![[\(title)]]"
    }

    // MARK: - Lines

    private static func lineBounds(in text: NSString, containing index: Int) -> NSRange {
        let clamped = min(max(0, index), max(0, text.length == 0 ? 0 : text.length - 1))
        let before = text.range(
            of: "\n",
            options: .backwards,
            range: NSRange(location: 0, length: clamped)
        )
        let lineStart = before.location == NSNotFound ? 0 : before.location + 1
        let after = text.range(
            of: "\n",
            options: [],
            range: NSRange(location: clamped, length: text.length - clamped)
        )
        let lineEnd = after.location == NSNotFound ? text.length : after.location
        return NSRange(location: lineStart, length: max(0, lineEnd - lineStart))
    }

    private static func isBlank(_ text: NSString, line: NSRange) -> Bool {
        guard line.length > 0, line.location != NSNotFound else { return true }
        return text.substring(with: line)
            .trimmingCharacters(in: .whitespaces)
            .isEmpty
    }
}
