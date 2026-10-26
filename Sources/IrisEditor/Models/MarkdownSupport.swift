import AppKit
import Foundation
import UniformTypeIdentifiers

/// Markdown-specific file type identifiers shared across open/save panels and file naming.
enum MarkdownFileType {
    /// A Markdown document (`public.markdown`).
    static let markdown = UTType(exportedAs: "public.markdown", conformingTo: .plainText)

    /// The set of content types Iris treats as editable Markdown.
    static var editable: [UTType] {
        [markdown, .plainText, .text]
    }

    /// The default extension used for new and exported documents.
    static let defaultExtension = "md"
}

/// Strips common Markdown syntax so document statistics count visible content, not markup.
enum MarkdownPlainText {

    /// Number of visible words after removing Markdown markers.
    static func words(in text: String) -> Int {
        stripped(text).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Number of visible characters after removing Markdown markers (whitespace included).
    static func characters(in text: String) -> Int {
        stripped(text).count
    }

    /// Removes the common Markdown syntax characters without a full parser.
    static func stripped(_ text: String) -> String {
        var result = text

        // Obsidian-style wiki links: keep the visible label, not the brackets/target.
        result = result.replacingOccurrences(
            of: #"\[\[[^\]\n|]+\|([^\]\n]+)\]\]"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\[\[([^\]\n]+)\]\]"#,
            with: "$1",
            options: .regularExpression
        )

        // Inline code markers (backticks).
        result = result.replacingOccurrences(of: "`", with: "")

        // Emphasis and strong markers.
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "~~", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")

        // Strip line-lead markers (headings, quotes, lists, fences) on a per-line basis so
        // we don't rely on regex line anchors.
        let lines = result.components(separatedBy: "\n")
        let cleaned = lines.map { line -> String in
            var line = line
            line = line.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks.
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                return ""
            }

            // Headings.
            let headingCount = line.prefix { $0 == "#" }.count
            if headingCount > 0, headingCount <= 6 {
                let trimmed = line.dropFirst(headingCount)
                line = String(trimmed).trimmingCharacters(in: .whitespaces)
            }

            // Block quote.
            if line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            // Unordered list.
            if line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("+") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            // Ordered list.
            if let dotIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }),
               line[line.startIndex] >= "0" && line[line.startIndex] <= "9" {
                let prefix = line[line.startIndex...dotIndex]
                if prefix.allSatisfy({ $0.isNumber || $0 == "." || $0 == ")" }) {
                    line = String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                }
            }

            return line
        }

        result = cleaned.joined(separator: "\n")
        return result
    }
}

/// Lightweight Markdown syntax highlighting for the AppKit text view.
///
/// Rather than mutating TextKit's attributed storage (which would wipe user formatting and
/// add churn on every keystroke), this produces `(range, token)` pairs that the text view
/// applies as *temporary attributes*. Temporary attributes ride on top of the base string,
/// are cheap to invalidate, and never mutate user content.
enum MarkdownHighlighter {

    enum Token: Equatable {
        case heading
        case emphasis
        case strong
        case inlineCode
        case fencedCode
        case blockquote
        case link
        case wikiLink
        case listMarker
        case horizontalRule
    }

    struct Highlight: Equatable {
        let nsRange: NSRange
        let token: Token
    }

    /// Scans `text` and returns the character ranges that should be tinted.
    ///
    /// The scanner is line-oriented and allocation-aware: it is called on the main thread
    /// after every edit (debounced by the caller), so it stays roughly linear in the size
    /// of the document.
    static func highlights(in text: String) -> [Highlight] {
        guard !text.isEmpty else { return [] }

        let ns = text as NSString
        let length = ns.length
        var result: [Highlight] = []
        result.reserveCapacity(length / 24)

        var inFence = false
        var fenceMarker = ""
        var fenceStart = NSNotFound

        var location = 0
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let lineLength = (line as NSString).length
            let lineRange = NSRange(location: location, length: lineLength)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks: ``` or ~~~
            if let fence = leadingFenceMarker(in: trimmed) {
                if !inFence {
                    inFence = true
                    fenceMarker = fence
                    fenceStart = lineRange.location
                } else if fence == fenceMarker {
                    if fenceStart != NSNotFound {
                        result.append(Highlight(
                            nsRange: NSRange(location: fenceStart, length: NSMaxRange(lineRange) - fenceStart),
                            token: .fencedCode
                        ))
                    }
                    inFence = false
                    fenceMarker = ""
                    fenceStart = NSNotFound
                }
            } else if inFence {
                result.append(Highlight(nsRange: lineRange, token: .fencedCode))
            } else if !trimmed.isEmpty {
                scanBlockLine(line, lineRange: lineRange, into: &result)
            }

            location += lineLength + 1 // +1 for the "\n" separator
        }

        if inFence, fenceStart != NSNotFound, fenceStart < length {
            result.append(Highlight(nsRange: NSRange(location: fenceStart, length: length - fenceStart), token: .fencedCode))
        }

        return result
    }

    private static func leadingFenceMarker(in trimmed: String) -> String? {
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func scanBlockLine(
        _ line: String,
        lineRange: NSRange,
        into result: inout [Highlight]
    ) {
        let nsLine = line as NSString
        let base = lineRange.location
        let leadingWhitespace = countLeadingWhitespace(in: nsLine)

        // Headings: 1-6 # marks followed by a space or end-of-line.
        if let headingCount = leadingHeadingCount(in: nsLine) {
            result.append(Highlight(nsRange: lineRange, token: .heading))
            let contentStart = headingCount
            let remainder = NSRange(
                location: contentStart,
                length: max(0, nsLine.length - contentStart)
            )
            scanInline(nsLine, contentRange: remainder, base: base, into: &result)
            return
        }

        // Block quotes.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") {
            let markerLength = countRun(of: 62, in: nsLine, from: leadingWhitespace) // '>'
            result.append(Highlight(
                nsRange: NSRange(location: base + leadingWhitespace, length: markerLength),
                token: .blockquote
            ))
            return
        }

        // Unordered list markers: - , * , + followed by a space.
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            result.append(Highlight(
                nsRange: NSRange(location: base + leadingWhitespace, length: 1),
                token: .listMarker
            ))
        }

        // Ordered list markers: "1. " or "1)".
        if let orderedLength = leadingOrderedListLength(in: nsLine, leadingWhitespace: leadingWhitespace) {
            result.append(Highlight(
                nsRange: NSRange(location: base + leadingWhitespace, length: orderedLength),
                token: .listMarker
            ))
        }

        // Horizontal rules.
        if isHorizontalRule(trimmed) {
            result.append(Highlight(nsRange: lineRange, token: .horizontalRule))
            return
        }

        // Inline content.
        scanInline(nsLine, contentRange: NSRange(location: 0, length: nsLine.length), base: base, into: &result)
    }

    private static func countLeadingWhitespace(in ns: NSString) -> Int {
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c != 32 && c != 9 { break } // space, tab
            i += 1
        }
        return i
    }

    private static func leadingHeadingCount(in ns: NSString) -> Int? {
        var i = 0
        while i < min(6, ns.length), ns.character(at: i) == 35 { i += 1 } // '#'
        guard i > 0 else { return nil }
        if i < ns.length {
            let next = ns.character(at: i)
            if next != 32 && next != 9 { return nil } // must be followed by space/tab/EOL
        }
        return i
    }

    private static func countRun(of target: unichar, in ns: NSString, from start: Int) -> Int {
        var i = start
        while i < ns.length, ns.character(at: i) == target { i += 1 }
        return i - start
    }

    private static func leadingOrderedListLength(in ns: NSString, leadingWhitespace: Int) -> Int? {
        var i = leadingWhitespace
        while i < ns.length, isDigit(ns.character(at: i)) { i += 1 }
        let digitCount = i - leadingWhitespace
        guard digitCount > 0, i < ns.length else { return nil }

        let dot = ns.character(at: i)
        guard dot == 46 || dot == 41 else { return nil } // '.' or ')'

        if dot == 46, i + 1 < ns.length, ns.character(at: i + 1) == 32 { // ". "
            return digitCount + 2
        }
        if dot == 41 { // ")"
            return digitCount + 1
        }
        return nil
    }

    private static func isDigit(_ c: unichar) -> Bool {
        c >= 48 && c <= 57
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        let set = Set(compact)
        guard set.count == 1, let char = set.first, char == "-" || char == "*" || char == "_" else {
            return false
        }
        return true
    }

    private static func scanInline(_ ns: NSString, contentRange: NSRange, base: Int, into result: inout [Highlight]) {
        guard contentRange.length > 0 else { return }
        let end = NSMaxRange(contentRange)
        var i = contentRange.location

        while i < end {
            let c = ns.character(at: i)

            // Obsidian-style wiki links: [[target]] or [[target|label]].
            if c == 91, i + 1 < end, ns.character(at: i + 1) == 91,
               let close = findWikiLinkClose(ns, from: i + 2, end: end) {
                result.append(Highlight(
                    nsRange: NSRange(location: base + i, length: close + 2 - i),
                    token: .wikiLink
                ))
                i = close + 2
                continue
            }

            // Inline code.
            if c == 96 {
                if let close = findMatchingBacktick(ns, from: i, end: end) {
                    result.append(Highlight(
                        nsRange: NSRange(location: base + i, length: close - i + 1),
                        token: .inlineCode
                    ))
                    i = close + 1
                    continue
                }
            }

            // Strong / emphasis.
            if c == 42 || c == 95 { // '*' or '_'
                let run = countRun(of: c, in: ns, from: i)
                result.append(Highlight(
                    nsRange: NSRange(location: base + i, length: run),
                    token: run >= 2 ? .strong : .emphasis
                ))
                i += run
                continue
            }

            i += 1
        }

        scanLinks(ns, contentRange: contentRange, base: base, into: &result)
    }

    private static func findMatchingBacktick(_ ns: NSString, from start: Int, end: Int) -> Int? {
        var i = start + 1
        while i < end {
            if ns.character(at: i) == 96 { return i }
            i += 1
        }
        return nil
    }

    private static func findWikiLinkClose(_ ns: NSString, from start: Int, end: Int) -> Int? {
        var i = start
        while i + 1 < end {
            if ns.character(at: i) == 10 { return nil } // no newlines inside wiki links
            if ns.character(at: i) == 93, ns.character(at: i + 1) == 93 {
                return i
            }
            i += 1
        }
        return nil
    }

    private static func scanLinks(_ ns: NSString, contentRange: NSRange, base: Int, into result: inout [Highlight]) {
        let substring = ns.substring(with: contentRange)
        var searchStart = substring.startIndex

        while let openBracket = substring[searchStart...].firstIndex(of: "[") {
            guard let closeBracket = substring[openBracket...].firstIndex(of: "]") else { break }
            let afterClose = substring.index(after: closeBracket)
            guard afterClose < substring.endIndex, substring[afterClose] == "(" else {
                searchStart = substring.index(after: openBracket)
                continue
            }
            guard let closeParen = substring[afterClose...].firstIndex(of: ")") else { break }

            let labelRange = substring.index(after: openBracket)..<closeBracket
            let urlRange = substring.index(after: afterClose)..<closeParen

            let labelOffset = substring.distance(from: substring.startIndex, to: labelRange.lowerBound)
            let labelLength = substring.distance(from: labelRange.lowerBound, to: labelRange.upperBound)
            let urlOffset = substring.distance(from: substring.startIndex, to: urlRange.lowerBound)
            let urlLength = substring.distance(from: urlRange.lowerBound, to: urlRange.upperBound)

            result.append(Highlight(
                nsRange: NSRange(location: base + contentRange.location + labelOffset, length: labelLength),
                token: .link
            ))
            result.append(Highlight(
                nsRange: NSRange(location: base + contentRange.location + urlOffset, length: urlLength),
                token: .link
            ))

            searchStart = substring.index(after: closeParen)
        }
    }
}
