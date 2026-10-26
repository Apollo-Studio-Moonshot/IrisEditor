import Foundation

/// A parsed Markdown block, sufficient for the preview renderer.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case blockQuote(lines: [String])
    case codeBlock(language: String?, lines: [String])
    case unorderedList(items: [String])
    case orderedList(items: [MarkdownOrderedItem])
    case table(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
    case thematicBreak
}

struct MarkdownOrderedItem: Equatable {
    let number: Int
    let text: String
}

/// Per-column alignment from a GFM pipe-table delimiter row (`:---`, `:---:`, `---:`).
enum MarkdownTableAlignment: Equatable {
    case left, center, right
}

/// A lightweight line-based Markdown block parser used by the preview.
///
/// It intentionally covers the common subset (headings, lists, quotes, fenced code,
/// rules, paragraphs) and leaves inline styling to `AttributedString(markdown:)`.
enum MarkdownBlockParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n").map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var unordered: [String] = []
        var ordered: [MarkdownOrderedItem] = []
        var openFence: String?
        var fenceLanguage: String?
        var codeLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        func flushQuote() {
            if !quote.isEmpty {
                blocks.append(.blockQuote(lines: quote))
                quote = []
            }
        }

        func flushLists() {
            if !unordered.isEmpty {
                blocks.append(.unorderedList(items: unordered))
                unordered = []
            }
            if !ordered.isEmpty {
                blocks.append(.orderedList(items: ordered))
                ordered = []
            }
        }

        func flushAll() {
            flushParagraph()
            flushQuote()
            flushLists()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Pipe tables need two-line lookahead (header row + delimiter row), so they
            // are detected here and consume their own rows before the loop continues.
            if openFence == nil,
               let table = MarkdownTableParser.table(startingAt: index - 1, in: lines) {
                flushAll()
                blocks.append(.table(
                    header: table.header,
                    alignments: table.alignments,
                    rows: table.rows
                ))
                index = table.nextIndex
                continue
            }

            // Inside a fenced code block: keep lines verbatim until the closing fence.
            if let fence = openFence {
                if closingFence(trimmed, marker: fence) {
                    blocks.append(.codeBlock(language: fenceLanguage, lines: codeLines))
                    openFence = nil
                    fenceLanguage = nil
                    codeLines = []
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if let (marker, language) = openingFence(trimmed) {
                flushAll()
                openFence = marker
                fenceLanguage = language
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if isHorizontalRule(trimmed) {
                flushAll()
                blocks.append(.thematicBreak)
                continue
            }

            if let (level, headingText) = heading(in: trimmed) {
                flushAll()
                blocks.append(.heading(level: level, text: headingText))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushLists()
                var content = String(trimmed.dropFirst())
                if content.first == " " { content.removeFirst() }
                quote.append(content)
                continue
            }

            if trimmed.count >= 2, "-*+".contains(trimmed.first!), trimmed.dropFirst().first == " " {
                flushParagraph()
                flushQuote()
                if !ordered.isEmpty {
                    blocks.append(.orderedList(items: ordered))
                    ordered = []
                }
                unordered.append(String(trimmed.dropFirst(2)))
                continue
            }

            if let item = orderedItem(in: trimmed) {
                flushParagraph()
                flushQuote()
                if !unordered.isEmpty {
                    blocks.append(.unorderedList(items: unordered))
                    unordered = []
                }
                ordered.append(item)
                continue
            }

            flushQuote()
            flushLists()
            paragraph.append(trimmed)
        }

        // An unclosed fence still renders as a code block (matches common editors).
        if openFence != nil {
            blocks.append(.codeBlock(language: fenceLanguage, lines: codeLines))
        }
        flushAll()
        return blocks
    }

    // MARK: - Line classifiers

    private static func openingFence(_ trimmed: String) -> (marker: String, language: String?)? {
        let marker: String
        if trimmed.hasPrefix("```") { marker = "```" }
        else if trimmed.hasPrefix("~~~") { marker = "~~~" }
        else { return nil }
        let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let language = info.split(separator: " ").first.map(String.init)
        return (marker, language)
    }

    private static func closingFence(_ trimmed: String, marker: String) -> Bool {
        !trimmed.isEmpty
            && trimmed.replacingOccurrences(of: " ", with: "") == marker
            && trimmed.hasPrefix(marker)
    }

    private static func heading(in trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        for character in trimmed {
            if character == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        if rest.isEmpty { return (level, "") }
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func orderedItem(in trimmed: String) -> MarkdownOrderedItem? {
        var digits = ""
        for character in trimmed {
            if character.isNumber { digits.append(character) } else { break }
        }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
        let remainder = afterDigits.dropFirst()
        guard remainder.isEmpty || remainder.first == " " || remainder.first == "\t" else { return nil }
        return MarkdownOrderedItem(number: number, text: remainder.trimmingCharacters(in: .whitespaces))
    }
}

/// Parses GFM pipe tables (`| a | b |` + `|---|:--:|` + data rows).
///
/// Used by `MarkdownBlockParser` via two-line lookahead: a table is only recognised when
/// a header row containing a pipe is followed by a valid delimiter row whose column count
/// matches.
enum MarkdownTableParser {
    struct Table {
        let header: [String]
        let alignments: [MarkdownTableAlignment]
        let rows: [[String]]
        /// Index of the first line *after* the table.
        let nextIndex: Int
    }

    static func table(startingAt start: Int, in lines: [String]) -> Table? {
        guard start < lines.count,
              lines[start].contains("|"),
              start + 1 < lines.count,
              let alignments = delimiterAlignments(for: lines[start + 1]) else {
            return nil
        }

        let header = splitRow(lines[start])
        guard header.count == alignments.count else { return nil }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // A table ends at the first blank line or line without a pipe.
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            var row = splitRow(raw)
            // Pad or truncate rows to the header width, like GFM renderers do.
            if row.count < alignments.count {
                row.append(contentsOf: Array(repeating: "", count: alignments.count - row.count))
            } else if row.count > alignments.count {
                row = Array(row.prefix(alignments.count))
            }
            rows.append(row)
            index += 1
        }

        return Table(header: header, alignments: alignments, rows: rows, nextIndex: index)
    }

    /// Column cells for a pipe-table row, with leading/trailing bars stripped and
    /// escaped pipes (`\|`) kept inside their cell.
    static func splitRow(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }

        // Stash `\|` behind a sentinel so escaped pipes survive the split.
        let sentinel = "\u{0}"
        content = content.replacingOccurrences(of: "\\|", with: sentinel)
        return content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { cell in
                String(cell)
                    .replacingOccurrences(of: sentinel, with: "|")
                    .trimmingCharacters(in: .whitespaces)
            }
    }

    /// Returns per-column alignments when `line` is a valid delimiter row, else nil.
    static func delimiterAlignments(for line: String) -> [MarkdownTableAlignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return nil }

        let cells = splitRow(line)
        guard !cells.isEmpty else { return nil }

        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            let compact = cell.replacingOccurrences(of: " ", with: "")
            guard !compact.isEmpty, compact.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }
            let dashes = compact.filter { $0 == "-" }
            guard !dashes.isEmpty else { return nil }

            let left = compact.hasPrefix(":")
            let right = compact.hasSuffix(":")
            if left, right {
                alignments.append(.center)
            } else if right {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        return alignments
    }
}
