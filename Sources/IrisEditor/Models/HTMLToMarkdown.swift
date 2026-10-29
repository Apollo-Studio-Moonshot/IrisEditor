import Foundation

// MARK: - HTMLToMarkdown

/// A deliberately small HTML → Markdown converter used for the "Paste as Markdown"
/// command. It handles the tags that commonly appear on the macOS pasteboard
/// (headers, paragraphs, bold/italic, links, images, lists, blockquotes, code, hr)
/// and strips everything else into plain text.
enum HTMLToMarkdown {

    static func convert(_ html: String) -> String {
        var s = html

        // Remove comments.
        s = s.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)

        // Lists are nesting-aware, so they are converted before the tag-stripping passes
        // and stored behind placeholder tokens (regex `<li>` replacement cannot nest).
        var lists: [String: String] = [:]
        s = extractLists(s, store: &lists)

        // Collapse whitespace between blocks first.
        s = s.replacingOccurrences(of: #">[ \t\r\n]+<"#, with: "><", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        // Block-level tags → newlines + marker.
        for (pattern, replacement) in blockReplacements {
            s = s.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Blockquote — each wrapped newline becomes "\n> ".
        s = replaceAll(in: s, pattern: #"<blockquote\b[^>]*>([\s\S]*?)</blockquote>"#, reOptions: .caseInsensitive) { m in
            let content = m[1].replacingOccurrences(of: "\n", with: "\n> ")
            return "\n\n> \(content)\n\n"
        }

        // Inline formatting.
        s = s.replacingOccurrences(of: #"<strong[^>]*>([\s\S]*?)</strong>"#, with: "**$1**", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<b[^>]*>([\s\S]*?)</b>"#, with: "**$1**", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<em[^>]*>([\s\S]*?)</em>"#, with: "*$1*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<i[^>]*>([\s\S]*?)</i>"#, with: "*$1*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<del[^>]*>([\s\S]*?)</del>"#, with: "~~$1~~", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<s[^>]*>([\s\S]*?)</s>"#, with: "~~$1~~", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<code[^>]*>([\s\S]*?)</code>"#, with: "`$1`", options: [.regularExpression, .caseInsensitive])

        // Links and images.
        s = replaceAll(in: s, pattern: #"<a\b[^>]*\bhref=["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, reOptions: .caseInsensitive) { m in
            "[" + m[2] + "](" + m[1] + ")"
        }
        s = replaceAll(in: s, pattern: #"<img\b[^>]*\bsrc=["']([^"']+)["'][^>]*\balt=["']([^"']*)["'][^>]*/?>"#, reOptions: .caseInsensitive) { m in
            "![\(m[2])](\(m[1]))"
        }
        s = replaceAll(in: s, pattern: #"<img\b[^>]*\bsrc=["']([^"']+)["'][^>]*/?>"#, reOptions: .caseInsensitive) { m in
            "![](\(m[1]))"
        }

        // Line breaks.
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "  \n", options: [.regularExpression, .caseInsensitive])

        // Lists — remove wrapping tags (bullet markers already added).
        s = s.replacingOccurrences(of: #"</?ul[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"</?ol[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])

        // Remove all remaining tags.
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // HTML entities.
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        s = s.replacingOccurrences(of: "&copy;", with: "©")
        s = s.replacingOccurrences(of: "&reg;", with: "®")
        s = s.replacingOccurrences(of: "&trade;", with: "™")
        s = s.replacingOccurrences(of: "&#8217;", with: "'")
        s = s.replacingOccurrences(of: "&#8216;", with: "'")
        s = s.replacingOccurrences(of: "&#8211;", with: "–")
        s = s.replacingOccurrences(of: "&#8212;", with: "—")
        s = s.replacingOccurrences(of: "&#8220;", with: "\"")
        s = s.replacingOccurrences(of: "&#8221;", with: "\"")

        // Collapse blank lines to at most two.
        s = s.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        // Restore the converted lists (they are kept out of the collapsing passes).
        for (placeholder, markdown) in lists {
            s = s.replacingOccurrences(of: placeholder, with: markdown)
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    // MARK: Lists

    private enum ListTokenKind {
        case open(String)
        case close(String)
        case item
    }

    private struct ListToken {
        let kind: ListTokenKind
        let start: Int
        /// Index just past the tag's closing `>`.
        let end: Int
    }

    /// Scans forward for the next `<ul>`/`<ol>`/`<li>`/`</ul>`/`</ol>`/`</li>` tag.
    private static func nextListToken(in ns: NSString, from index: Int) -> ListToken? {
        var cursor = index
        while cursor < ns.length {
            let search = NSRange(location: cursor, length: ns.length - cursor)
            let found = ns.range(of: "<", options: [], range: search)
            guard found.location != NSNotFound else { return nil }
            guard let tagEnd = ns.range(of: ">", options: [], range: NSRange(
                location: found.location,
                length: ns.length - found.location
            )).location as Int?, tagEnd != NSNotFound else { return nil }

            let inner = ns.substring(with: NSRange(
                location: found.location + 1,
                length: tagEnd - found.location - 1
            )).trimmingCharacters(in: .whitespaces)
            let isClosing = inner.hasPrefix("/")
            let name = (isClosing ? String(inner.dropFirst()) : inner)
                .prefix { !$0.isWhitespace && $0 != "/" }
                .lowercased()

            let tokenEnd = tagEnd + 1
            switch (isClosing, name) {
            case (true, "ul"): return ListToken(kind: .close("ul"), start: found.location, end: tokenEnd)
            case (true, "ol"): return ListToken(kind: .close("ol"), start: found.location, end: tokenEnd)
            case (true, "li"): return ListToken(kind: .close("li"), start: found.location, end: tokenEnd)
            case (false, "ul"): return ListToken(kind: .open("ul"), start: found.location, end: tokenEnd)
            case (false, "ol"): return ListToken(kind: .open("ol"), start: found.location, end: tokenEnd)
            case (false, "li"): return ListToken(kind: .item, start: found.location, end: tokenEnd)
            default: cursor = tokenEnd
            }
        }
        return nil
    }

    /// Replaces every `<ul>`/`<ol>` region with a placeholder token so the later
    /// tag-stripping passes cannot flatten the list structure.
    private static func extractLists(_ html: String, store: inout [String: String]) -> String {
        let ns = html as NSString
        var out = ""
        var cursor = 0
        var counter = 0

        while cursor < ns.length {
            guard let token = nextListToken(in: ns, from: cursor) else {
                out += ns.substring(from: cursor)
                break
            }
            if case .open = token.kind,
               let list = convertList(in: ns, at: token.start, depth: 0) {
                out += ns.substring(with: NSRange(location: cursor, length: token.start - cursor))
                let placeholder = "\u{1}LIST\(counter)\u{1}"
                store[placeholder] = list.markdown
                counter += 1
                out += "\n\n" + placeholder + "\n\n"
                cursor = list.end
            } else {
                // Not a list start (stray `</li>`, `<li>` outside a list, …).
                out += ns.substring(with: NSRange(location: cursor, length: token.end - cursor))
                cursor = token.end
            }
        }
        return out
    }

    private struct ConvertedItem {
        let content: String
        let nested: [String]
    }

    private static func convertList(
        in ns: NSString,
        at start: Int,
        depth: Int
    ) -> (markdown: String, end: Int)? {
        guard let opening = nextListToken(in: ns, from: start), opening.start == start,
              case let .open(name) = opening.kind else { return nil }

        var items: [ConvertedItem] = []
        var cursor = opening.end
        var end = ns.length

        while cursor < ns.length {
            guard let token = nextListToken(in: ns, from: cursor) else { break }
            switch token.kind {
            case .item:
                let item = convertItem(in: ns, at: token.end, depth: depth)
                items.append(item.value)
                cursor = item.end
            case let .close(closing):
                if closing == name {
                    end = token.end
                    cursor = ns.length
                } else {
                    cursor = token.end
                }
            case .open:
                // A nested list without an owning `<li>`: fold it in as its own item.
                if let nested = convertList(in: ns, at: token.start, depth: depth + 1) {
                    items.append(ConvertedItem(content: "", nested: [nested.markdown]))
                    cursor = nested.end
                } else {
                    cursor = token.end
                }
            }
        }

        return (render(items: items, ordered: name == "ol", depth: depth), end)
    }

    private static func convertItem(
        in ns: NSString,
        at contentStart: Int,
        depth: Int
    ) -> (value: ConvertedItem, end: Int) {
        var buffer = ""
        var nested: [String] = []
        var cursor = contentStart

        while cursor < ns.length {
            guard let token = nextListToken(in: ns, from: cursor) else { break }
            buffer += ns.substring(with: NSRange(location: cursor, length: token.start - cursor))
            switch token.kind {
            case .close("li"):
                return (itemValue(from: buffer, nested: nested), token.end)
            case let .close(other):
                if other == "ul" || other == "ol" {
                    // Malformed HTML: the item ends where its list ends.
                    return (itemValue(from: buffer, nested: nested), token.start)
                }
                buffer += ns.substring(with: NSRange(location: token.start, length: token.end - token.start))
                cursor = token.end
            case .open:
                if let sublist = convertList(in: ns, at: token.start, depth: depth + 1) {
                    nested.append(sublist.markdown)
                    cursor = sublist.end
                } else {
                    cursor = token.end
                }
            case .item:
                buffer += ns.substring(with: NSRange(location: token.start, length: token.end - token.start))
                cursor = token.end
            }
        }

        return (itemValue(from: buffer, nested: nested), ns.length)
    }

    private static func itemValue(from html: String, nested: [String]) -> ConvertedItem {
        var content = html

        // Task list items keep their checkbox state.
        if let checkbox = content.range(
            of: #"<input\b[^>]*\btype=["']?checkbox["']?[^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let tag = String(content[checkbox]).lowercased()
            content = content.replacingCharacters(in: checkbox, with: "")
            let checked = tag.contains("checked")
            content = (checked ? "[x] " : "[ ] ") + content
        }

        let markdown = convert(content)
        return ConvertedItem(content: markdown, nested: nested)
    }

    private static func render(items: [ConvertedItem], ordered: Bool, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []

        for (offset, item) in items.enumerated() {
            let marker = ordered ? "\(offset + 1). " : "- "
            let continuation = indent + String(repeating: " ", count: marker.count)
            let contentLines = item.content
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            if contentLines.isEmpty {
                lines.append((indent + marker).trimmingCharacters(in: .whitespaces))
            } else {
                for (index, line) in contentLines.enumerated() {
                    lines.append((index == 0 ? indent + marker : continuation) + line)
                }
            }
            lines.append(contentsOf: item.nested.filter { !$0.isEmpty })
        }

        return lines.joined(separator: "\n")
    }

    private static let blockReplacements: [(String, String)] = [
        (#"<h1\b[^>]*>([\s\S]*?)</h1>"#, "\n\n# $1\n\n"),
        (#"<h2\b[^>]*>([\s\S]*?)</h2>"#, "\n\n## $1\n\n"),
        (#"<h3\b[^>]*>([\s\S]*?)</h3>"#, "\n\n### $1\n\n"),
        (#"<h4\b[^>]*>([\s\S]*?)</h4>"#, "\n\n#### $1\n\n"),
        (#"<h5\b[^>]*>([\s\S]*?)</h5>"#, "\n\n##### $1\n\n"),
        (#"<h6\b[^>]*>([\s\S]*?)</h6>"#, "\n\n###### $1\n\n"),
        (#"<p\b[^>]*>([\s\S]*?)</p>"#, "\n\n$1\n\n"),
        (#"<div\b[^>]*>([\s\S]*?)</div>"#, "\n$1\n"),
        (#"<pre\b[^>]*>([\s\S]*?)</pre>"#, "\n\n```\n$1\n```\n\n"),
        (#"<hr\s*/?>"#, "\n\n---\n\n"),
        (#"<li\b[^>]*>([\s\S]*?)</li>"#, "- $1\n"),
    ]

    /// Applies an NSRegularExpression repeatedly, calling the closure for each match with
    /// a 1-indexed capture-group subscript wrapper.
    private static func replaceAll(
        in s: String,
        pattern: String,
        reOptions: NSRegularExpression.Options = [],
        transform: (MatchResult) -> String
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: reOptions) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out = s
        var offset = 0
        for match in matches.reversed() {
            let mr = MatchResult(ns: ns, match: match)
            let replacement = transform(mr)
            let adjusted = NSRange(location: match.range.location + offset, length: match.range.length)
            out = (out as NSString).replacingCharacters(in: adjusted, with: replacement)
            // Offsets are UTF-16 based, so the delta must be too: `replacement.count`
            // counts `Character`s and drifts as soon as an emoji is involved.
            offset += (replacement as NSString).length - match.range.length
        }
        return out
    }

    /// A tiny wrapper around NSTextCheckingResult that provides 1-indexed subscripting for
    /// capture groups matching `NSRegularExpression.replacementString` semantics.
    struct MatchResult {
        let ns: NSString
        let match: NSTextCheckingResult

        subscript(_ group: Int) -> String {
            let range = match.range(at: group)
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { return "" }
            return ns.substring(with: range)
        }
    }
}
