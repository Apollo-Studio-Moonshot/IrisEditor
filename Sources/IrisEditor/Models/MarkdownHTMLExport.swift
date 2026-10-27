import Foundation

/// Renders a Markdown document as a standalone HTML file for sharing, printing, or
/// opening in a browser. It reuses the same block and inline parsers as the preview, so
/// exported output matches what Iris shows on screen.
enum MarkdownHTMLExport {

    /// A complete HTML document with embedded, appearance-aware styling.
    static func document(from markdown: String, title: String) -> String {
        let safeTitle = escape(title)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(safeTitle)</title>
        <style>
        :root {
          color-scheme: light dark;
          --text: #1c1c1e;
          --muted: #6c6c70;
          --background: #ffffff;
          --surface: #f2f2f7;
          --border: #d1d1d6;
          --accent: #6c5ce7;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --text: #f2f2f7;
            --muted: #a1a1a6;
            --background: #1c1c1e;
            --surface: #2c2c2e;
            --border: #3a3a3c;
            --accent: #a29bfe;
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          padding: 3rem 1.5rem 5rem;
          background: var(--background);
          color: var(--text);
          font: 16px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
        }
        main { max-width: 46rem; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.8em 0 0.6em; }
        h1 { font-size: 2rem; }
        h2 { font-size: 1.55rem; }
        h3 { font-size: 1.3rem; }
        h4 { font-size: 1.1rem; }
        h5, h6 { font-size: 1rem; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
        a { color: var(--accent); }
        blockquote {
          margin-left: 0;
          padding: 0.15em 0 0.15em 1em;
          border-left: 3px solid var(--border);
          color: var(--muted);
        }
        code {
          font: 0.92em/1.5 ui-monospace, "SF Mono", Menlo, monospace;
          background: var(--surface);
          border-radius: 4px;
          padding: 0.1em 0.3em;
        }
        pre {
          overflow-x: auto;
          padding: 0.9em 1em;
          background: var(--surface);
          border-radius: 8px;
        }
        pre code { background: none; padding: 0; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid var(--border); padding: 0.45em 0.7em; }
        th { background: var(--surface); text-align: left; }
        hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        </style>
        </head>
        <body>
        <main>
        \(body(from: markdown))
        </main>
        </body>
        </html>
        """
    }

    /// Just the rendered `<main>` contents, useful for tests or embedding.
    static func body(from markdown: String) -> String {
        let parsed = MarkdownBlockParser.parseDocument(markdown)
        return render(blocks: parsed.blocks, references: parsed.references)
    }

    // MARK: - Blocks

    private static func render(
        blocks: [MarkdownBlock],
        references: [String: MarkdownLinkReference]
    ) -> String {
        blocks.map { render(block: $0, references: references) }.joined(separator: "\n")
    }

    private static func render(
        block: MarkdownBlock,
        references: [String: MarkdownLinkReference]
    ) -> String {
        switch block {
        case .heading(let level, let text):
            let tag = "h\(min(max(level, 1), 6))"
            return "<\(tag)>\(renderInline(text, references: references))</\(tag)>"

        case .paragraph(let text):
            return "<p>\(renderInline(text, references: references))</p>"

        case .blockQuote(let blocks):
            return "<blockquote>\n\(render(blocks: blocks, references: references))\n</blockquote>"

        case .codeBlock(let language, let lines):
            let classAttribute = language.map {
                " class=\"language-\(escapeAttribute($0))\""
            } ?? ""
            let code = escape(lines.joined(separator: "\n"))
            return "<pre><code\(classAttribute)>\(code)</code></pre>"

        case .list(let ordered, let start, let items):
            let tag = ordered ? "ol" : "ul"
            let startAttribute = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let renderedItems = items.map { item -> String in
                "<li>\n\(render(blocks: item.blocks, references: references))\n</li>"
            }.joined(separator: "\n")
            return "<\(tag)\(startAttribute)>\n\(renderedItems)\n</\(tag)>"

        case .table(let header, let alignments, let rows):
            return renderTable(header: header, alignments: alignments, rows: rows, references: references)

        case .thematicBreak:
            return "<hr>"

        case .htmlBlock(let lines):
            // The preview shows non-table HTML blocks readably rather than executing
            // arbitrary markup, so the exported file does the same.
            return "<pre class=\"html-block\"><code>\(escape(lines.joined(separator: "\n")))</code></pre>"
        }
    }

    private static func renderTable(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]],
        references: [String: MarkdownLinkReference]
    ) -> String {
        var output = "<table>\n<thead>\n<tr>\n"
        for (column, cell) in header.enumerated() {
            output += "<th\(alignmentStyle(for: column, in: alignments))>"
            output += renderInline(cell, references: references)
            output += "</th>\n"
        }
        output += "</tr>\n</thead>\n"

        if !rows.isEmpty {
            output += "<tbody>\n"
            for row in rows {
                output += "<tr>\n"
                for (column, cell) in row.enumerated() {
                    output += "<td\(alignmentStyle(for: column, in: alignments))>"
                    output += renderInline(cell, references: references)
                    output += "</td>\n"
                }
                output += "</tr>\n"
            }
            output += "</tbody>\n"
        }
        output += "</table>"
        return output
    }

    private static func alignmentStyle(
        for column: Int,
        in alignments: [MarkdownTableAlignment]
    ) -> String {
        guard column < alignments.count else { return "" }
        switch alignments[column] {
        case .left: return " style=\"text-align: left\""
        case .center: return " style=\"text-align: center\""
        case .right: return " style=\"text-align: right\""
        }
    }

    // MARK: - Inlines

    private static func renderInline(
        _ text: String,
        references: [String: MarkdownLinkReference]
    ) -> String {
        let inlines = MarkdownInlineParser(references: references).parse(text)
        return inlines.map { renderInline($0, references: references) }.joined()
    }

    private static func renderInline(
        _ inline: MarkdownInline,
        references: [String: MarkdownLinkReference]
    ) -> String {
        switch inline {
        case .text(let value):
            return escape(value)

        case .emphasis(let children):
            return "<em>\(renderInline(children, references: references))</em>"

        case .strong(let children):
            return "<strong>\(renderInline(children, references: references))</strong>"

        case .strikethrough(let children):
            return "<del>\(renderInline(children, references: references))</del>"

        case .code(let value):
            return "<code>\(escape(value))</code>"

        case .link(let destination, let title, let children):
            let label = renderInline(children, references: references)
            guard let href = safeDestination(destination) else { return label }
            let titleAttribute = title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
            return "<a href=\"\(escapeAttribute(href))\"\(titleAttribute)>\(label)</a>"

        case .image(let source, let alt, let title):
            guard let source = safeDestination(source) else {
                return escape(alt.isEmpty ? "Image" : alt)
            }
            let titleAttribute = title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
            return "<img src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(alt))\"\(titleAttribute)>"

        case .wikiLink(let target, let label):
            return "<a href=\"\(escapeAttribute(wikiHref(for: target)))\">\(escape(label))</a>"

        case .softBreak:
            return "\n"

        case .hardBreak:
            return "<br>\n"

        case .html(let value):
            // The preview shows unknown inline HTML as literal text instead of running it,
            // so the exported document escapes it for the same safe behavior.
            return escape(value)
        }
    }

    private static func renderInline(
        _ inlines: [MarkdownInline],
        references: [String: MarkdownLinkReference]
    ) -> String {
        inlines.map { renderInline($0, references: references) }.joined()
    }

    // MARK: - Helpers

    /// Relative destinations and the schemes a browser can safely handle. Markdown can
    /// contain `javascript:` or `data:` links, which must not become active on export.
    private static func safeDestination(_ destination: String) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return trimmed
        }
        let allowed: Set<String> = ["http", "https", "mailto", "file"]
        return allowed.contains(scheme) ? trimmed : nil
    }

    /// Relative note link that will resolve beside the exported file.
    private static func wikiHref(for target: String) -> String {
        let pieces = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let note = String(pieces.first ?? "")
        let extensionName = (note as NSString).pathExtension.lowercased()
        let file = ["md", "markdown"].contains(extensionName)
            ? note
            : note + ".md"
        guard pieces.count > 1 else { return file }
        return file + "#" + String(pieces[1])
    }

    private static func escape(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        return result
    }

    private static func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "'", with: "&#39;")
    }
}
