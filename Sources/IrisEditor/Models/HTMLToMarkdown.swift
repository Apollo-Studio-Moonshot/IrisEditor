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

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

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
            offset += replacement.count - match.range.length
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
