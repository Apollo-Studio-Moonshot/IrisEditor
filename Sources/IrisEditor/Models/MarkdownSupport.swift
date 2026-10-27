import AppKit
import Foundation
import UniformTypeIdentifiers

/// Markdown-specific file type identifiers shared across open/save panels and file naming.
enum MarkdownFileType {
    /// The system Markdown type used by Finder, Quick Look, and other editors.
    static let markdown = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )

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

    /// Removes block markers and inline Markdown so statistics count only visible text.
    ///
    /// Inline spans are resolved with the same parser the preview uses, so intraword
    /// underscores (`snake_case`), escaped markers (`\*`), and link targets (`[label](url)`) are
    /// preserved/counted exactly as they render. Fenced code content is kept verbatim so its
    /// code is counted while its fence markers are not.
    static func stripped(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var result: [String] = []
        var fenceMarker: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker {
                if trimmed.hasPrefix(marker) {
                    fenceMarker = nil
                } else {
                    result.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenceMarker = String(trimmed.prefix(3))
                continue
            }

            // Thematic breaks and Setext underlines carry no visible content.
            if isRuleLine(trimmed) {
                continue
            }

            let content = stripBlockPrefix(from: trimmed)
            guard !content.isEmpty else {
                result.append("")
                continue
            }

            result.append(MarkdownInlineParser().parse(content).plainText)
        }

        return result.joined(separator: "\n")
    }

    /// Removes one level of heading, quote, list, or task-list marker from a line.
    private static func stripBlockPrefix(from line: String) -> String {
        var content = line

        // Headings: 1-6 hashes followed by whitespace.
        let headingHashes = content.prefix { $0 == "#" }.count
        if (1...6).contains(headingHashes) {
            let rest = content.dropFirst(headingHashes)
            if rest.first == " " || rest.first == "\t" {
                content = String(rest).trimmingCharacters(in: .whitespaces)
            }
        }

        // Block quotes (possibly nested).
        while content.hasPrefix(">") {
            content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Unordered lists and task-list checkboxes.
        if let first = content.first, "-*+".contains(first) {
            let rest = content.dropFirst()
            if rest.first == " " || rest.first == "\t" {
                content = String(rest).trimmingCharacters(in: .whitespaces)
                if let marker = content.first, marker == "[", content.count >= 3 {
                    let status = content[content.index(after: content.startIndex)]
                    let close = content[content.index(content.startIndex, offsetBy: 2)]
                    if close == "]", status == " " || status == "x" || status == "X" {
                        content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        // Ordered lists: digits followed by '.' or ')' and whitespace.
        let digits = content.prefix { $0.isNumber }
        if !digits.isEmpty, content.count > digits.count {
            let delimiter = content[content.index(content.startIndex, offsetBy: digits.count)]
            if delimiter == "." || delimiter == ")" {
                let rest = content.dropFirst(digits.count + 1)
                if rest.first == " " || rest.first == "\t" {
                    content = String(rest).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return content
    }

    /// A thematic break or Setext underline made entirely of one marker character.
    private static func isRuleLine(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 2, let first = compact.first,
              "-=*_".contains(first) else {
            return false
        }
        return compact.allSatisfy { $0 == first }
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

        // Headings: 1-6 # marks (after up to three spaces) followed by whitespace/EOL.
        if leadingWhitespace <= 3,
           let headingCount = leadingHeadingCount(in: nsLine, from: leadingWhitespace) {
            result.append(Highlight(nsRange: lineRange, token: .heading))
            let contentStart = leadingWhitespace + headingCount
            let remainder = NSRange(
                location: contentStart,
                length: max(0, nsLine.length - contentStart)
            )
            scanInline(nsLine, contentRange: remainder, base: base, into: &result)
            return
        }

        // Block quotes, including nested `> >` markers. Inline content after the marker
        // is still scanned so emphasis and links inside quotes stay highlighted.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if leadingWhitespace <= 3, trimmed.hasPrefix(">") {
            var cursor = leadingWhitespace
            while cursor < nsLine.length, nsLine.character(at: cursor) == 62 { // '>'
                cursor += 1
                if cursor < nsLine.length {
                    let next = nsLine.character(at: cursor)
                    if next == 32 || next == 9 {
                        cursor += 1
                    }
                }
            }
            result.append(Highlight(
                nsRange: NSRange(location: base + leadingWhitespace, length: cursor - leadingWhitespace),
                token: .blockquote
            ))
            let remainder = NSRange(location: cursor, length: max(0, nsLine.length - cursor))
            scanInline(nsLine, contentRange: remainder, base: base, into: &result)
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

    private static func leadingHeadingCount(in ns: NSString, from start: Int) -> Int? {
        var i = start
        while i < min(start + 6, ns.length), ns.character(at: i) == 35 { i += 1 } // '#'
        let count = i - start
        guard count > 0 else { return nil }
        if i < ns.length {
            let next = ns.character(at: i)
            if next != 32 && next != 9 { return nil } // must be followed by space/tab/EOL
        }
        return count
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
