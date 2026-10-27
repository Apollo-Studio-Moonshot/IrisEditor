import Foundation

/// A single `key: value` pair from a document's YAML frontmatter.
struct MarkdownFrontmatterField: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case text, number, boolean, date, list, tags, empty
    }

    /// Stable position-based identity so SwiftUI diffing does not thrash between parses.
    let id: Int
    let key: String
    let value: String
    let kind: Kind

    /// A human-friendly label: `created_at` → `Created at`.
    var displayKey: String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        guard let first = spaced.first else { return key }
        return first.uppercased() + spaced.dropFirst()
    }

    var listValues: [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Parsed YAML frontmatter at the very top of a Markdown document.
///
/// Only a block that opens with a lone `---` on the first line and closes with `---`
/// (or `...`) is treated as frontmatter, matching Obsidian and most Markdown tools.
/// Everything after the closing fence is the document body; the raw block is kept so
/// callers can conceal it from the preview and statistics.
struct MarkdownFrontmatter: Equatable {
    let fields: [MarkdownFrontmatterField]
    let raw: String
    let body: String
    /// Number of source lines occupied by the block, including both fences.
    let lineCount: Int

    var title: String? {
        field(named: "title")
    }

    var tags: [String] {
        let keys = ["tags", "tag", "keywords"]
        for key in keys {
            if let raw = field(named: key) {
                let values = raw
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
                    .filter { !$0.isEmpty }
                if !values.isEmpty { return values }
            }
        }
        return []
    }

    func field(named name: String) -> String? {
        fields.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

enum MarkdownFrontmatterParser {

    /// Returns `nil` when the document does not start with a complete frontmatter block.
    static func parse(_ text: String) -> MarkdownFrontmatter? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // A UTF-8 BOM should not stop frontmatter detection.
        let source = normalized.hasPrefix("\u{FEFF}")
            ? String(normalized.dropFirst())
            : normalized

        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        var closingIndex: Int?
        var index = 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                closingIndex = index
                break
            }
            index += 1
        }
        guard let closingIndex else { return nil }

        let yamlLines = Array(lines[1..<closingIndex])
        let fields = parseFields(yamlLines)
        let rawLines = Array(lines[0...closingIndex])
        let raw = rawLines.joined(separator: "\n")

        let bodyLines = Array(lines[(closingIndex + 1)...])
        var body = bodyLines.joined(separator: "\n")
        // Drop a single leading blank line left after the closing fence.
        if body.hasPrefix("\n") { body.removeFirst() }

        return MarkdownFrontmatter(
            fields: fields,
            raw: raw,
            body: body,
            lineCount: closingIndex + 1
        )
    }

    // MARK: - Minimal YAML

    private static func parseFields(_ lines: [String]) -> [MarkdownFrontmatterField] {
        var fields: [(key: String, value: String, kind: MarkdownFrontmatterField.Kind)] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            // Nested/list item lines are attached to the preceding key.
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                let item = String(trimmed.dropFirst(trimmed == "-" ? 1 : 2))
                    .trimmingCharacters(in: .whitespaces)
                if !fields.isEmpty {
                    let previous = fields[fields.count - 1]
                    let value = previous.value.isEmpty
                        ? unquote(item)
                        : previous.value + ", " + unquote(item)
                    fields[fields.count - 1] = (previous.key, value, .list)
                }
                index += 1
                continue
            }

            guard let colon = trimmed.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.hasPrefix("[") else {
                index += 1
                continue
            }

            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)

            // Block scalars (`key: |` or `key: >`) collect the indented lines below.
            if value == "|" || value == ">" {
                var collected: [String] = []
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    if next.trimmingCharacters(in: .whitespaces).isEmpty {
                        collected.append("")
                        index += 1
                        continue
                    }
                    guard next.hasPrefix(" ") || next.hasPrefix("\t") else { break }
                    collected.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                fields.append((key, collected.joined(separator: " ").trimmingCharacters(in: .whitespaces), .text))
                continue
            }

            index += 1
            let normalizedKey = key.lowercased()
            let cleaned = unquote(value)
            fields.append((key, cleaned, kind(for: cleaned, key: normalizedKey, raw: value)))
        }

        return fields.enumerated().map { position, field in
            MarkdownFrontmatterField(
                id: position,
                key: field.key,
                value: field.value,
                kind: field.kind
            )
        }
    }

    private static func kind(
        for value: String,
        key: String,
        raw: String
    ) -> MarkdownFrontmatterField.Kind {
        if ["tags", "tag", "keywords", "aliases", "alias"].contains(key) {
            return .tags
        }
        if value.isEmpty { return .empty }
        if raw.hasPrefix("[") || raw.hasPrefix("- ") { return .list }
        if value.caseInsensitiveCompare("true") == .orderedSame
            || value.caseInsensitiveCompare("false") == .orderedSame {
            return .boolean
        }
        if Double(value) != nil { return .number }
        if value.range(of: #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?)?$"#,
                       options: .regularExpression) != nil {
            return .date
        }
        if value.contains(", ") { return .list }
        return .text
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first
        let last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        if first == "[", last == "]" {
            return String(value.dropFirst().dropLast())
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: ", ")
        }
        return value
    }
}
