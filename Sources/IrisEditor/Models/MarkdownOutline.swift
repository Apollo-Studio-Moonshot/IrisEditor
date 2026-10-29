import Foundation

/// Extracts the heading hierarchy used by the document outline sidebar.
///
/// ATX (`# Heading`) and Setext (`Heading` + `===`) headings are supported, headings
/// inside fenced code blocks are ignored, and inline Markdown is flattened to its
/// visible text so the sidebar shows `Bold title`, not `**Bold title**`.
enum MarkdownOutline {
    struct Heading: Identifiable, Equatable {
        let level: Int
        let title: String
        let line: Int

        var id: String { "\(line):\(level):\(title)" }
    }

    static func headings(in text: String) -> [Heading] {
        guard !text.isEmpty else { return [] }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // A YAML frontmatter block must never be read as content: its `---` fence and
        // `title: …` line would otherwise look like a Setext heading. Line numbers stay
        // document-relative so outline navigation still jumps to the right place.
        var lineOffset = 0
        var body = normalized
        if let frontmatter = MarkdownFrontmatterParser.parse(normalized) {
            lineOffset = frontmatter.lineCount
            body = frontmatter.body
        }

        let lines = body.components(separatedBy: "\n")

        var headings: [Heading] = []
        var fenceMarker: Character?
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = lineOffset + index + 1

            if let marker = fenceMarker {
                if isFence(trimmed, marker: marker) {
                    fenceMarker = nil
                }
                index += 1
                continue
            }

            if let marker = fenceMarkerStart(in: trimmed) {
                fenceMarker = marker
                index += 1
                continue
            }

            if let heading = atxHeading(in: line, lineNumber: lineNumber) {
                headings.append(heading)
                index += 1
                continue
            }

            // Setext heading: the underline is the second line and must be `===` or `---`.
            if !trimmed.isEmpty,
               canBeSetextContent(trimmed),
               index + 1 < lines.count,
               let level = setextLevel(for: lines[index + 1]) {
                let title = visibleTitle(from: trimmed)
                if !title.isEmpty {
                    headings.append(Heading(level: level, title: title, line: lineNumber))
                }
                index += 2
                continue
            }

            index += 1
        }

        return headings
    }

    private static func atxHeading(in line: String, lineNumber: Int) -> Heading? {
        var index = line.startIndex
        var spaces = 0
        while index < line.endIndex, line[index] == " ", spaces < 4 {
            index = line.index(after: index)
            spaces += 1
        }
        guard spaces <= 3 else { return nil }

        var hashes = 0
        while index < line.endIndex, line[index] == "#", hashes < 7 {
            index = line.index(after: index)
            hashes += 1
        }
        guard (1...6).contains(hashes) else { return nil }
        guard index == line.endIndex || line[index] == " " || line[index] == "\t" else {
            return nil
        }

        var content = String(line[index...]).trimmingCharacters(in: .whitespaces)
        content = trimmingTrailingHashes(content)
        let title = visibleTitle(from: content)
        guard !title.isEmpty else { return nil }
        return Heading(level: hashes, title: title, line: lineNumber)
    }

    private static func trimmingTrailingHashes(_ content: String) -> String {
        // A closing sequence is only a closing sequence when whitespace precedes the
        // run, so `# C#` keeps its hash while `# Title ###` drops the trailing run.
        guard let range = content.range(of: "\\s+#+\\s*$", options: .regularExpression) else {
            return content.trimmingCharacters(in: .whitespaces)
        }
        return String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private static func setextLevel(for line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == "=" || first == "-" else {
            return nil
        }
        guard trimmed.allSatisfy({ $0 == first }) else { return nil }
        return first == "=" ? 1 : 2
    }

    /// Excludes block constructs that cannot be Setext heading content, such as thematic
    /// breaks, quotes, and list items, so `---\n---` is not mistaken for a heading.
    private static func canBeSetextContent(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        if compact.count >= 3, let first = compact.first, "-*_".contains(first),
           compact.allSatisfy({ $0 == first }) {
            return false
        }

        guard let first = trimmed.first else { return false }
        if first == ">" || first == "-" || first == "*" || first == "+" {
            return false
        }

        if first.isNumber,
           let marker = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }),
           trimmed[trimmed.startIndex..<marker].allSatisfy(\.isNumber) {
            return false
        }

        return true
    }

    private static func fenceMarkerStart(in trimmed: String) -> Character? {
        guard trimmed.hasPrefix("```") else {
            return trimmed.hasPrefix("~~~") ? "~" : nil
        }
        return "`"
    }

    private static func isFence(_ trimmed: String, marker: Character) -> Bool {
        marker == "`" ? trimmed.hasPrefix("```") : trimmed.hasPrefix("~~~")
    }

    private static func visibleTitle(from raw: String) -> String {
        MarkdownInlineParser().parse(raw).plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
