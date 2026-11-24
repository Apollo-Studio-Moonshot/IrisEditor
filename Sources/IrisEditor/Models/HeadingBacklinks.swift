import Foundation

/// Heading-targeted wiki links (`[[Note#Heading]]`) turned into gutter marks.
enum HeadingBacklinkIndex {

    /// Wiki links in `text` that name a heading in some other note.
    ///
    /// `aliases` maps a lowercased title, relative path, or frontmatter alias to the
    /// note it names. A link with an empty note (`[[#Heading]]`) points at `sourceURL`
    /// and is dropped, because the gutter shows links from other notes.
    static func references(
        in text: String,
        sourceURL: URL,
        sourceTitle: String,
        aliases: [String: URL]
    ) -> [VaultHeadingReference] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        let sourcePath = sourceURL.standardizedFileURL.path
        var fence: Character?
        var results: [VaultHeadingReference] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(String(repeating: String(marker), count: 3)) {
                    fence = nil
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                fence = "`"
                continue
            }
            if trimmed.hasPrefix("~~~") {
                fence = "~"
                continue
            }

            let masked = maskingInlineCode(line)
            guard masked.contains("[[") else { continue }

            for link in headingLinks(in: masked) {
                guard let target = resolve(note: link.note, sourceURL: sourceURL, aliases: aliases) else {
                    continue
                }
                guard target.standardizedFileURL.path != sourcePath else { continue }
                results.append(
                    VaultHeadingReference(
                        sourceURL: sourceURL,
                        sourceTitle: sourceTitle,
                        line: index + 1,
                        excerpt: prefixExcerpt(line),
                        targetURL: target,
                        heading: link.heading
                    )
                )
            }
        }
        return results
    }

    /// Line numbers in `documentText` whose headings are the target of `references`.
    static func marks(
        in documentText: String,
        documentURL: URL,
        references: [VaultHeadingReference]
    ) -> [Int: [VaultBacklink]] {
        let targetPath = documentURL.standardizedFileURL.path
        let relevant = references.filter {
            $0.targetURL.standardizedFileURL.path == targetPath
                && $0.sourceURL.standardizedFileURL.path != targetPath
        }
        guard !relevant.isEmpty else { return [:] }

        var grouped: [Int: [VaultBacklink]] = [:]
        for heading in MarkdownOutline.headings(in: documentText) {
            let titleKey = normalize(heading.title)
            guard !titleKey.isEmpty else { continue }

            var sources: [VaultBacklink] = []
            var seen = Set<String>()
            for reference in relevant where matchKeys(reference.heading).contains(titleKey) {
                let identity = "\(reference.sourceURL.standardizedFileURL.path)#\(reference.line)"
                guard seen.insert(identity).inserted else { continue }
                sources.append(
                    VaultBacklink(
                        sourceURL: reference.sourceURL,
                        sourceTitle: reference.sourceTitle,
                        line: reference.line,
                        excerpt: reference.excerpt
                    )
                )
            }
            guard !sources.isEmpty else { continue }
            sources.sort { lhs, rhs in
                let order = lhs.sourceTitle.localizedStandardCompare(rhs.sourceTitle)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.line < rhs.line
            }
            grouped[heading.line, default: []].append(contentsOf: sources)
        }
        return grouped
    }

    /// Comparison key for a heading title or a `#fragment`.
    static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Keys a heading fragment can match: the whole fragment, and its last `#` piece.
    /// Block references (`^id`) match nothing.
    static func matchKeys(_ fragment: String) -> [String] {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("^") else { return [] }
        let full = normalize(trimmed)
        let last = trimmed.split(separator: "#").last.map { normalize(String($0)) } ?? full
        if full.isEmpty { return [] }
        if last.isEmpty || last == full { return [full] }
        return [full, last]
    }

    // MARK: - Parsing

    private static func headingLinks(in line: String) -> [(note: String, heading: String)] {
        guard let regex = wikiExpression else { return [] }
        let string = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: string.length))
        var links: [(note: String, heading: String)] = []

        for match in matches {
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            var target = string.substring(with: range)
            if let pipe = target.firstIndex(of: "|") {
                target = String(target[..<pipe])
            }
            guard let hash = target.firstIndex(of: "#") else { continue }
            let note = String(target[..<hash]).trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = String(target[target.index(after: hash)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heading.isEmpty else { continue }
            links.append((note, heading))
        }
        return links
    }

    private static func resolve(
        note: String,
        sourceURL: URL,
        aliases: [String: URL]
    ) -> URL? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return sourceURL }
        let lowered = trimmed.lowercased()
        if let url = aliases[lowered] { return url }
        let stripped = strippingExtension(lowered)
        if stripped != lowered, let url = aliases[stripped] { return url }
        return nil
    }

    private static func strippingExtension(_ path: String) -> String {
        for ext in [".md", ".markdown"] where path.hasSuffix(ext) {
            return String(path.dropLast(ext.count))
        }
        return path
    }

    private static func maskingInlineCode(_ line: String) -> String {
        var masked = ""
        var inside = false
        for character in line {
            if character == "`" {
                inside.toggle()
                masked.append(" ")
            } else {
                masked.append(inside ? " " : character)
            }
        }
        return masked
    }

    private static func prefixExcerpt(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 120 else { return trimmed }
        return String(trimmed.prefix(120)) + "…"
    }

    private static let wikiExpression = try? NSRegularExpression(
        pattern: #"\[\[([^\[\]]+)\]\]"#
    )
}
