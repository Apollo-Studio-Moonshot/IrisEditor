import Foundation

/// A parsed Markdown block, sufficient for the preview renderer.
///
/// Lists and block quotes are recursive, so containers inside containers (a quote in a
/// list in a quote) survive parsing instead of being flattened.
indirect enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case blockQuote(blocks: [MarkdownBlock])
    case codeBlock(language: String?, lines: [String])
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case table(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
    case thematicBreak
    case htmlBlock(lines: [String])
}

struct MarkdownListItem: Equatable {
    var blocks: [MarkdownBlock]
}

/// A link reference definition (`[label]: https://example.com "title"`), resolved by the
/// inline parser for `[text][label]`, `[label][]`, and `[label]` links.
struct MarkdownLinkReference: Equatable {
    let destination: String
    let title: String?
}

/// The full parse result: blocks plus the document's link reference definitions.
struct MarkdownDocument: Equatable {
    let blocks: [MarkdownBlock]
    let references: [String: MarkdownLinkReference]
}

/// Per-column alignment from a GFM pipe-table delimiter row (`:---`, `:---:`, `---:`).
enum MarkdownTableAlignment: Equatable {
    case left, center, right
}

/// A line-based Markdown block parser covering the Markdown Guide basic syntax.
///
/// Inline content is intentionally left as raw text; `MarkdownInlineParser` resolves it at
/// render time, when the document's reference definitions are available.
enum MarkdownBlockParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        parseDocument(text).blocks
    }

    static func parseDocument(_ text: String) -> MarkdownDocument {
        var references: [String: MarkdownLinkReference] = [:]
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let blocks = parseLines(lines, references: &references)
        return MarkdownDocument(blocks: blocks, references: references)
    }

    // MARK: - Block loop

    private static func parseLines(
        _ lines: [String],
        references: inout [String: MarkdownLinkReference]
    ) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let raw = lines[index]
            let indent = indentColumns(raw)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            let content = indent <= 3 ? dropIndent(raw, indent) : raw
            let contentTrimmed = content.trimmingCharacters(in: .whitespaces)

            // Fenced code block (at four spaces of indent it is an indented code block).
            if indent <= 3, let fence = openingFence(contentTrimmed) {
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeRaw = lines[index]
                    let codeIndent = indentColumns(codeRaw)
                    let stripped = codeIndent <= 3 ? dropIndent(codeRaw, codeIndent) : codeRaw
                    if codeIndent <= 3,
                       closingFence(stripped.trimmingCharacters(in: .whitespaces),
                                    marker: fence.marker,
                                    length: fence.length) {
                        index += 1
                        break
                    }
                    codeLines.append(dropIndent(codeRaw, indent))
                    index += 1
                }
                blocks.append(.codeBlock(language: fence.language, lines: codeLines))
                continue
            }

            // Indented code block: four spaces or one tab.
            if indent >= 4 {
                var codeLines: [String] = []
                while index < lines.count {
                    let codeRaw = lines[index]
                    if codeRaw.trimmingCharacters(in: .whitespaces).isEmpty {
                        codeLines.append("")
                        index += 1
                        continue
                    }
                    guard indentColumns(codeRaw) >= 4 else { break }
                    codeLines.append(dropIndent(codeRaw, 4))
                    index += 1
                }
                while codeLines.last?.isEmpty == true {
                    codeLines.removeLast()
                }
                if !codeLines.isEmpty {
                    blocks.append(.codeBlock(language: nil, lines: codeLines))
                }
                continue
            }

            // Link reference definition (consumed, not rendered).
            if let definition = referenceDefinition(content) {
                references[definition.label] = definition.reference
                index += 1
                continue
            }

            // Horizontal rule.
            if isThematicBreak(contentTrimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            // ATX heading.
            if let heading = atxHeading(contentTrimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Block quote: strip one `>` level and recursively parse the contents.
            if contentTrimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                var quoteIndex = index
                while quoteIndex < lines.count {
                    let quoteRaw = lines[quoteIndex]
                    let quoteIndent = indentColumns(quoteRaw)
                    let quoteContent = quoteIndent <= 3 ? dropIndent(quoteRaw, quoteIndent) : quoteRaw

                    if quoteContent.hasPrefix(">") {
                        var inner = String(quoteContent.dropFirst())
                        if inner.first == " " { inner.removeFirst() }
                        quoteLines.append(inner)
                        quoteIndex += 1
                        continue
                    }

                    if quoteRaw.trimmingCharacters(in: .whitespaces).isEmpty,
                       nextQuotedLine(after: quoteIndex, in: lines) {
                        quoteLines.append("")
                        quoteIndex += 1
                        continue
                    }
                    break
                }
                blocks.append(.blockQuote(blocks: parseLines(quoteLines, references: &references)))
                index = quoteIndex
                continue
            }

            // Ordered or unordered list.
            if let marker = listMarker(in: raw) {
                let result = parseList(
                    startingAt: index,
                    firstMarker: marker,
                    lines: lines,
                    references: &references
                )
                blocks.append(result.block)
                index = result.nextIndex
                continue
            }

            // Block-level HTML.
            if isHTMLBlockStart(contentTrimmed) {
                var htmlLines: [String] = []
                while index < lines.count {
                    let htmlRaw = lines[index]
                    if htmlRaw.trimmingCharacters(in: .whitespaces).isEmpty { break }
                    htmlLines.append(stripLeadingWhitespace(htmlRaw))
                    index += 1
                }
                blocks.append(.htmlBlock(lines: htmlLines))
                continue
            }

            // GFM pipe table (extension already supported by the preview). Checked after
            // containers so quoted/list rows containing pipes are not mistaken for tables.
            if let table = MarkdownTableParser.table(startingAt: index, in: lines) {
                blocks.append(.table(
                    header: table.header,
                    alignments: table.alignments,
                    rows: table.rows
                ))
                index = table.nextIndex
                continue
            }

            // Paragraph (or Setext heading when an underline follows).
            var paragraphLines: [String] = [stripLeadingWhitespace(raw)]
            index += 1
            var setextLevel: Int?
            while index < lines.count {
                let nextRaw = lines[index]
                if nextRaw.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if let level = setextUnderline(nextRaw) {
                    setextLevel = level
                    index += 1
                    break
                }
                if startsBlock(nextRaw) { break }
                paragraphLines.append(stripLeadingWhitespace(nextRaw))
                index += 1
            }

            let text = paragraphLines.joined(separator: "\n")
            if let level = setextLevel {
                blocks.append(.heading(
                    level: level,
                    text: text.trimmingCharacters(in: .whitespaces)
                ))
            } else {
                blocks.append(.paragraph(text: text))
            }
        }

        return blocks
    }

    // MARK: - Lists

    private struct ListMarker {
        let ordered: Bool
        let start: Int
        let indent: Int
        let contentIndent: Int
        let content: String
    }

    private static func parseList(
        startingAt startIndex: Int,
        firstMarker: ListMarker,
        lines: [String],
        references: inout [String: MarkdownLinkReference]
    ) -> (block: MarkdownBlock, nextIndex: Int) {
        let listIndent = firstMarker.indent
        let ordered = firstMarker.ordered
        var items: [MarkdownListItem] = []
        var index = startIndex

        while index < lines.count {
            guard let marker = listMarker(in: lines[index]),
                  marker.indent == listIndent,
                  marker.ordered == ordered else { break }

            var itemLines: [String] = [marker.content]
            index += 1
            var sawBlankLine = false

            while index < lines.count {
                let raw = lines[index]

                if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                    itemLines.append("")
                    sawBlankLine = true
                    index += 1
                    continue
                }

                if let nextMarker = listMarker(in: raw),
                   nextMarker.indent == listIndent,
                   nextMarker.ordered == ordered {
                    break
                }

                let indent = indentColumns(raw)
                if indent >= marker.contentIndent {
                    itemLines.append(dropIndent(raw, marker.contentIndent))
                    sawBlankLine = false
                    index += 1
                    continue
                }

                // A blank line followed by dedented content ends the list.
                if sawBlankLine { break }

                // Lazy paragraph continuation, but never swallow a new block.
                if startsBlock(raw) { break }
                itemLines.append(stripLeadingWhitespace(raw))
                index += 1
            }

            items.append(MarkdownListItem(blocks: parseLines(itemLines, references: &references)))

            guard index < lines.count,
                  let nextMarker = listMarker(in: lines[index]),
                  nextMarker.indent == listIndent,
                  nextMarker.ordered == ordered else {
                break
            }
        }

        return (.list(ordered: ordered, start: ordered ? firstMarker.start : 1, items: items), index)
    }

    private static func listMarker(in line: String) -> ListMarker? {
        let indent = indentColumns(line)
        guard indent <= 3 else { return nil }

        let rest = Array(dropIndent(line, indent))
        guard let first = rest.first else { return nil }

        let ordered: Bool
        let start: Int
        let markerWidth: Int

        if first == "-" || first == "*" || first == "+" {
            ordered = false
            start = 1
            markerWidth = 1
        } else if first.isNumber {
            var digits = ""
            var cursor = 0
            while cursor < rest.count, rest[cursor].isNumber, digits.count < 9 {
                digits.append(rest[cursor])
                cursor += 1
            }
            guard cursor < rest.count,
                  rest[cursor] == "." || rest[cursor] == ")",
                  let number = Int(digits) else { return nil }
            ordered = true
            start = number
            markerWidth = digits.count + 1
        } else {
            return nil
        }

        if markerWidth < rest.count {
            let afterMarker = rest[markerWidth]
            guard afterMarker == " " || afterMarker == "\t" else { return nil }
        }

        var spacing = 0
        var contentStart = markerWidth
        while contentStart < rest.count,
              rest[contentStart] == " " || rest[contentStart] == "\t" {
            spacing += 1
            contentStart += 1
        }

        // CommonMark: 1-4 spaces belong to the content indent; more than four leaves the
        // extra spaces in the content (where they can start an indented code block).
        let effectiveSpacing = (spacing == 0 || spacing > 4) ? 1 : spacing
        var content = contentStart < rest.count ? String(rest[contentStart...]) : ""
        if spacing > 4 {
            content = String(repeating: " ", count: spacing - 1) + content
        }

        return ListMarker(
            ordered: ordered,
            start: start,
            indent: indent,
            contentIndent: indent + markerWidth + effectiveSpacing,
            content: content
        )
    }

    // MARK: - Line classifiers

    private static func openingFence(
        _ trimmed: String
    ) -> (marker: Character, length: Int, language: String?)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let runLength = trimmed.prefix { $0 == first }.count
        guard runLength >= 3 else { return nil }

        let info = String(trimmed.dropFirst(runLength)).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }

        let language = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return (first, runLength, language?.isEmpty == true ? nil : language)
    }

    private static func closingFence(_ trimmed: String, marker: Character, length: Int) -> Bool {
        let runLength = trimmed.prefix { $0 == marker }.count
        guard runLength >= length else { return false }
        return trimmed.dropFirst(runLength).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }

        let rest = trimmed.dropFirst(hashes.count)
        if let first = rest.first {
            guard first == " " || first == "\t" else { return nil }
        }

        var text = rest.trimmingCharacters(in: .whitespaces)

        // Optional closing sequence: a run of `#` preceded by whitespace.
        if text.last == "#" {
            var hashStart = text.endIndex
            while hashStart > text.startIndex, text[text.index(before: hashStart)] == "#" {
                hashStart = text.index(before: hashStart)
            }
            if hashStart == text.startIndex {
                text = ""
            } else {
                let preceding = text[text.index(before: hashStart)]
                if preceding == " " || preceding == "\t" {
                    text = String(text[..<text.index(before: hashStart)])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return (hashes.count, text)
    }

    private static func setextUnderline(_ line: String) -> Int? {
        let indent = indentColumns(line)
        guard indent <= 3 else { return nil }
        let content = dropIndent(line, indent).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        if content.allSatisfy({ $0 == "=" }) { return 1 }
        if content.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func startsBlock(_ raw: String) -> Bool {
        let indent = indentColumns(raw)
        guard indent <= 3 else { return false }
        let content = dropIndent(raw, indent)
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { return true }
        if openingFence(trimmed) != nil { return true }
        if isThematicBreak(trimmed) { return true }
        if atxHeading(trimmed) != nil { return true }
        if trimmed.hasPrefix(">") { return true }
        if listMarker(in: raw) != nil { return true }
        if isHTMLBlockStart(trimmed) { return true }
        return false
    }

    // MARK: - References

    private static func referenceDefinition(
        _ content: String
    ) -> (label: String, reference: MarkdownLinkReference)? {
        let characters = Array(content)
        guard characters.first == "[" else { return nil }

        var cursor = 1
        var label = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\", cursor + 1 < characters.count {
                label.append(characters[cursor + 1])
                cursor += 2
                continue
            }
            if character == "]" { break }
            label.append(character)
            cursor += 1
        }

        guard cursor + 1 < characters.count,
              characters[cursor] == "]",
              characters[cursor + 1] == ":" else {
            return nil
        }
        cursor += 2

        while cursor < characters.count,
              characters[cursor] == " " || characters[cursor] == "\t" {
            cursor += 1
        }

        guard let target = MarkdownLinkSyntax.parseInlineLinkTarget(characters, from: cursor) else {
            return nil
        }

        var end = target.end
        while end < characters.count,
              characters[end] == " " || characters[end] == "\t" {
            end += 1
        }
        guard end == characters.count else { return nil }

        let normalized = MarkdownLinkSyntax.normalizeLabel(label)
        guard !normalized.isEmpty else { return nil }
        return (
            normalized,
            MarkdownLinkReference(destination: target.destination, title: target.title)
        )
    }

    // MARK: - Block-level HTML

    private static let blockHTMLTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body",
        "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header",
        "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem",
        "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search",
        "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead",
        "title", "tr", "track", "ul",
    ]

    private static func isHTMLBlockStart(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("<!--") || trimmed.hasPrefix("<![CDATA[")
            || trimmed.hasPrefix("<?") || trimmed.hasPrefix("<!") {
            return true
        }
        guard trimmed.hasPrefix("<") else { return false }

        var cursor = trimmed.index(after: trimmed.startIndex)
        if cursor < trimmed.endIndex, trimmed[cursor] == "/" {
            cursor = trimmed.index(after: cursor)
        }
        var name = ""
        while cursor < trimmed.endIndex,
              trimmed[cursor].isLetter || trimmed[cursor].isNumber || trimmed[cursor] == "-" {
            name.append(trimmed[cursor])
            cursor = trimmed.index(after: cursor)
        }
        guard !name.isEmpty, cursor < trimmed.endIndex else { return false }
        let afterName = trimmed[cursor]
        guard afterName == " " || afterName == "\t" || afterName == ">"
            || afterName == "/" else {
            return false
        }
        return blockHTMLTags.contains(name.lowercased())
    }

    // MARK: - Whitespace helpers

    static func indentColumns(_ line: String) -> Int {
        var columns = 0
        for character in line {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 4 - (columns % 4)
            } else {
                break
            }
        }
        return columns
    }

    static func dropIndent(_ line: String, _ columns: Int) -> String {
        guard columns > 0 else { return line }
        var remaining = columns
        var index = line.startIndex
        var padding = ""

        while index < line.endIndex, remaining > 0 {
            let character = line[index]
            if character == " " {
                remaining -= 1
                index = line.index(after: index)
            } else if character == "\t" {
                let width = 4 - ((columns - remaining) % 4)
                index = line.index(after: index)
                if width <= remaining {
                    remaining -= width
                } else {
                    padding = String(repeating: " ", count: width - remaining)
                    remaining = 0
                }
            } else {
                break
            }
        }

        return padding + String(line[index...])
    }

    private static func stripLeadingWhitespace(_ line: String) -> String {
        dropIndent(line, indentColumns(line))
    }

    private static func nextQuotedLine(after index: Int, in lines: [String]) -> Bool {
        var cursor = index + 1
        while cursor < lines.count,
              lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
            cursor += 1
        }
        guard cursor < lines.count else { return false }
        let line = lines[cursor]
        let indent = indentColumns(line)
        guard indent <= 3 else { return false }
        return dropIndent(line, indent).hasPrefix(">")
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
