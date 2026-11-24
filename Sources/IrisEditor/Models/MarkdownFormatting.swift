import Foundation

/// Marker-aware Markdown formatting applied to an `NSTextView` buffer.
///
/// Word-boundary and marker logic operates on Swift `Character`s (grapheme clusters),
/// so surrogate-pair characters such as emoji are never split. UTF-16 ranges are only
/// produced at the boundaries where the AppKit text view needs them.
enum MarkdownFormatting {

    struct Result: Equatable {
        let text: String
        let selection: NSRange
        /// The UTF-16 range in the *original* text that actually changed.
        let changedRange: NSRange
        /// The replacement for `changedRange`.
        let replacement: String
    }

    /// Wraps or unwraps the selection in `prefix`/`suffix` markers.
    ///
    /// A line-prefix marker (one that ends with a space, such as `"# "`, `"- "`, `"> "`)
    /// toggles at the start of each affected line — it is never appended to the end of
    /// the text, which would produce invalid Markdown. Any other marker is treated as a
    /// symmetric wrapper around the selection.
    static func toggle(
        text: String,
        selection range: NSRange,
        prefix: String,
        suffix: String? = nil
    ) -> Result? {
        let resolvedSuffix = suffix ?? prefix

        if prefix == resolvedSuffix && isHeadingMarker(prefix) {
            return toggleHeading(text: text, selection: range, marker: prefix)
        }

        if prefix == "1. " && prefix == resolvedSuffix {
            return toggleOrderedList(text: text, selection: range)
        }

        if prefix == resolvedSuffix && prefix.hasSuffix(" ") {
            return toggleLinePrefix(text: text, selection: range, marker: prefix)
        }

        guard let selected = substring(of: text, at: range) else { return nil }

        let target: NSRange
        let targetText: String
        if selected.isEmpty {
            target = wordRange(in: text, aroundUtf16Location: range.location)
            guard target.length > 0, let wordText = substring(of: text, at: target) else { return nil }
            targetText = wordText
        } else {
            target = range
            targetText = selected
        }

        let alreadyWrapped = targetText.hasPrefix(prefix)
            && targetText.hasSuffix(resolvedSuffix)
            && targetText.count >= prefix.count + resolvedSuffix.count

        if alreadyWrapped {
            let inner = String(targetText.dropFirst(prefix.count).dropLast(resolvedSuffix.count))
            let newSelection = NSRange(location: target.location, length: (inner as NSString).length)
            let newText = (text as NSString).replacingCharacters(in: target, with: inner)
            return Result(
                text: newText,
                selection: newSelection,
                changedRange: target,
                replacement: inner
            )
        }

        let wrapped = prefix + targetText + resolvedSuffix
        let newText = (text as NSString).replacingCharacters(in: target, with: wrapped)
        return Result(
            text: newText,
            selection: NSRange(location: target.location, length: (wrapped as NSString).length),
            changedRange: target,
            replacement: wrapped
        )
    }

    // MARK: - Headings

    /// `# ` … `###### `, including the trailing space.
    private static func isHeadingMarker(_ marker: String) -> Bool {
        let hashes = marker.dropLast()
        return marker.hasSuffix(" ")
            && (1...6).contains(hashes.count)
            && hashes.allSatisfy { $0 == "#" }
    }

    /// Leading ATX marker, allowing the three spaces Markdown permits before `#`.
    private static func splitATX(_ line: String) -> (indent: Substring, marker: String, rest: Substring)? {
        var index = line.startIndex
        var spaces = 0
        while index < line.endIndex, line[index] == " ", spaces < 3 {
            spaces += 1
            index = line.index(after: index)
        }
        let indentEnd = index
        var hashes = 0
        while index < line.endIndex, line[index] == "#", hashes < 6 {
            hashes += 1
            index = line.index(after: index)
        }
        guard hashes >= 1, index < line.endIndex, line[index] == " " else { return nil }
        let markerEnd = line.index(after: index)
        return (line[..<indentEnd], String(line[indentEnd..<markerEnd]), line[markerEnd...])
    }

    /// Sets or clears an ATX level. A different level replaces the old marker
    /// instead of stacking (`## ` applied to `# Title` is `## Title`, not `## # Title`).
    private static func toggleHeading(text: String, selection: NSRange, marker: String) -> Result? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let anchor = min(max(0, selection.location), ns.length)
        let firstLineRange = ns.lineRange(for: NSRange(location: anchor, length: 0))
        let trailingPoint = min(max(0, NSMaxRange(selection) - 1), ns.length)
        let lastLineRange = ns.lineRange(for: NSRange(location: trailingPoint, length: 0))
        let blockRange = NSRange(
            location: firstLineRange.location,
            length: NSMaxRange(lastLineRange) - firstLineRange.location
        )
        guard blockRange.length > 0 else { return nil }

        var lines: [(content: String, terminator: String)] = []
        ns.enumerateSubstrings(in: blockRange, options: .byLines) { line, lineRange, enclosingRange, _ in
            let terminatorLength = enclosingRange.upperBound - NSMaxRange(lineRange)
            let terminator = terminatorLength > 0
                ? ns.substring(with: NSRange(location: NSMaxRange(lineRange), length: terminatorLength))
                : ""
            lines.append((content: line ?? "", terminator: terminator))
        }
        guard !lines.isEmpty else { return nil }

        let contentLines = lines.filter { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !contentLines.isEmpty else { return nil }

        let allExact = contentLines.allSatisfy { splitATX($0.content)?.marker == marker }

        var rebuilt = ""
        for line in lines {
            let isBlank = line.content.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                rebuilt += line.content
            } else if let parts = splitATX(line.content) {
                rebuilt += allExact
                    ? String(parts.indent) + String(parts.rest)
                    : String(parts.indent) + marker + String(parts.rest)
            } else if allExact {
                rebuilt += line.content
            } else {
                rebuilt += marker + line.content
            }
            rebuilt += line.terminator
        }

        let newText = ns.replacingCharacters(in: blockRange, with: rebuilt)
        return Result(
            text: newText,
            selection: NSRange(location: blockRange.location, length: (rebuilt as NSString).length),
            changedRange: blockRange,
            replacement: rebuilt
        )
    }

    /// `1. ` at the start of a line, or a longer `12. ` marker already there.
    private static func orderedPrefixLength(in line: String) -> Int? {
        var index = line.startIndex
        var digits = 0
        while index < line.endIndex, line[index].isNumber, digits < 9 {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex, line[index] == "." else { return nil }
        let space = line.index(after: index)
        guard space < line.endIndex, line[space] == " " else { return nil }
        return line.distance(from: line.startIndex, to: line.index(after: space))
    }

    /// Numbers each selected line. Applying it again removes `1. `, `2. `, and so on
    /// instead of writing `1. 1. ` in front of an existing item.
    private static func toggleOrderedList(text: String, selection: NSRange) -> Result? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let anchor = min(max(0, selection.location), ns.length)
        let firstLineRange = ns.lineRange(for: NSRange(location: anchor, length: 0))
        let trailingPoint = min(max(0, NSMaxRange(selection) - 1), ns.length)
        let lastLineRange = ns.lineRange(for: NSRange(location: trailingPoint, length: 0))
        let blockRange = NSRange(
            location: firstLineRange.location,
            length: NSMaxRange(lastLineRange) - firstLineRange.location
        )
        guard blockRange.length > 0 else { return nil }

        var lines: [(content: String, terminator: String)] = []
        ns.enumerateSubstrings(in: blockRange, options: .byLines) { line, lineRange, enclosingRange, _ in
            let terminatorLength = enclosingRange.upperBound - NSMaxRange(lineRange)
            let terminator = terminatorLength > 0
                ? ns.substring(with: NSRange(location: NSMaxRange(lineRange), length: terminatorLength))
                : ""
            lines.append((content: line ?? "", terminator: terminator))
        }
        guard !lines.isEmpty else { return nil }

        let contentLines = lines.filter { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !contentLines.isEmpty else { return nil }
        let remove = contentLines.allSatisfy { orderedPrefixLength(in: $0.content) != nil }

        var rebuilt = ""
        var number = 1
        for line in lines {
            let isBlank = line.content.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                rebuilt += line.content
            } else if let length = orderedPrefixLength(in: line.content) {
                let rest = String(line.content.dropFirst(length))
                rebuilt += remove ? rest : "\(number). \(rest)"
                if !remove { number += 1 }
            } else if remove {
                rebuilt += line.content
            } else {
                rebuilt += "\(number). \(line.content)"
                number += 1
            }
            rebuilt += line.terminator
        }

        let newText = ns.replacingCharacters(in: blockRange, with: rebuilt)
        return Result(
            text: newText,
            selection: NSRange(location: blockRange.location, length: (rebuilt as NSString).length),
            changedRange: blockRange,
            replacement: rebuilt
        )
    }

    // MARK: - Line-prefix markers

    private static func toggleLinePrefix(text: String, selection: NSRange, marker: String) -> Result? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let anchor = min(max(0, selection.location), ns.length)
        let firstLineRange = ns.lineRange(for: NSRange(location: anchor, length: 0))
        let trailingPoint = min(max(0, NSMaxRange(selection) - 1), ns.length)
        let lastLineRange = ns.lineRange(for: NSRange(location: trailingPoint, length: 0))
        let blockRange = NSRange(
            location: firstLineRange.location,
            length: NSMaxRange(lastLineRange) - firstLineRange.location
        )
        guard blockRange.length > 0 else { return nil }

        var lines: [(content: String, terminator: String)] = []
        ns.enumerateSubstrings(in: blockRange, options: .byLines) { line, lineRange, enclosingRange, _ in
            let terminatorLength = enclosingRange.upperBound - NSMaxRange(lineRange)
            let terminator = terminatorLength > 0
                ? ns.substring(with: NSRange(location: NSMaxRange(lineRange), length: terminatorLength))
                : ""
            lines.append((content: line ?? "", terminator: terminator))
        }
        guard !lines.isEmpty else { return nil }

        let contentLines = lines.filter { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !contentLines.isEmpty else { return nil }

        let allPrefixed = contentLines.allSatisfy { $0.content.hasPrefix(marker) }

        var rebuilt = ""
        for line in lines {
            let isBlank = line.content.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                rebuilt += line.content
            } else if allPrefixed {
                rebuilt += String(line.content.dropFirst(marker.count))
            } else {
                rebuilt += marker + line.content
            }
            rebuilt += line.terminator
        }

        let newText = ns.replacingCharacters(in: blockRange, with: rebuilt)
        return Result(
            text: newText,
            selection: NSRange(location: blockRange.location, length: (rebuilt as NSString).length),
            changedRange: blockRange,
            replacement: rebuilt
        )
    }

    // MARK: - Word expansion for empty selections

    /// The grapheme-safe equivalent of the old UTF-16 scalar scan: characters composed
    /// of surrogate pairs are handled as single units instead of crashing the scanner.
    private static func wordRange(in text: String, aroundUtf16Location location: Int) -> NSRange {
        let characters = Array(text)
        var utf16Starts = [Int](repeating: 0, count: characters.count + 1)
        for index in characters.indices {
            utf16Starts[index + 1] = utf16Starts[index] + characters[index].utf16.count
        }

        var right = 0
        while right < characters.count, utf16Starts[right] < location { right += 1 }

        var start = right
        while start > 0, isWordCharacter(characters[start - 1]) { start -= 1 }

        var end = right
        while end < characters.count, isWordCharacter(characters[end]) { end += 1 }

        if start == end { return NSRange(location: location, length: 0) }
        return NSRange(
            location: utf16Starts[start],
            length: utf16Starts[end] - utf16Starts[start]
        )
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    // MARK: - UTF-16 bridging

    private static func substring(of text: String, at range: NSRange) -> String? {
        let ns = text as NSString
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= ns.length else {
            return nil
        }
        return ns.substring(with: range)
    }
}
