import Foundation

/// Renders a Markdown document as a standalone HTML file for sharing, printing, or
/// opening in a browser. It reuses the same block and inline parsers as the preview, so
/// exported output matches what Iris shows on screen.
enum MarkdownHTMLExport {

    /// A complete HTML document with embedded, appearance-aware styling.
    ///
    /// Pass a `PreviewTheme` to make the exported page match the palette the user
    /// selected for the in-app preview. The default keeps the system-aware palette.
    static func document(
        from markdown: String,
        title: String,
        using theme: PreviewTheme = .system
    ) -> String {
        let safeTitle = escape(title)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(safeTitle)</title>
        <style>
        \(paletteCSS(for: theme))
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
        mark {
          background: var(--highlight, #fff2a8);
          color: inherit;
          border-radius: 3px;
          padding: 0 0.15em;
        }
        .callout {
          margin: 0 0 1em;
          padding: 0.7em 0.9em;
          border-left: 3px solid var(--callout, var(--accent));
          border-radius: 6px;
          background: color-mix(in srgb, var(--callout, var(--accent)) 10%, transparent);
        }
        .callout > summary {
          cursor: pointer;
          font-weight: 600;
          list-style: none;
          display: flex;
          gap: 0.4em;
          align-items: baseline;
          color: var(--callout, var(--accent));
        }
        .callout > summary::-webkit-details-marker { display: none; }
        .callout-body > :first-child { margin-top: 0.5em; }
        .callout-body > :last-child { margin-bottom: 0; }
        .callout-note, .callout-abstract, .callout-info, .callout-todo { --callout: #4a7bd8; }
        .callout-tip, .callout-success { --callout: #2c9a5e; }
        .callout-question, .callout-example { --callout: #8c59c9; }
        .callout-warning { --callout: #d98a10; }
        .callout-failure, .callout-danger, .callout-bug { --callout: #d43f3f; }
        .callout-quote { --callout: #6b7280; }
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
        .tok-keyword { color: #c0398f; }
        .tok-string { color: #c0392b; }
        .tok-comment { color: #8e8e93; font-style: italic; }
        .tok-number { color: #2d6cdf; }
        .tok-type { color: #0a8f8f; }
        .tok-function { color: #7b4fd1; }
        .tok-property { color: #c46a1b; }
        .math-block {
          margin: 1em 0;
          padding: 0.8em 1em;
          text-align: center;
          font-family: ui-serif, "New York", Georgia, serif;
          font-size: 1.12em;
          background: var(--surface);
          border-radius: 8px;
          overflow-x: auto;
        }
        .math-inline { font-family: ui-serif, "New York", Georgia, serif; font-style: italic; }
        .task-list { list-style: none; padding-left: 0.4em; }
        .task-list li.task { list-style: none; }
        .task-list input[type="checkbox"] { margin-right: 0.35em; }
        .mermaid { margin: 1em 0; overflow-x: auto; text-align: center; }
        .mermaid svg { max-width: 100%; height: auto; }
        .properties {
          margin: 0 0 2em;
          padding: 0.9em 1.1em;
          border: 1px solid var(--border);
          border-radius: 12px;
          background: color-mix(in srgb, var(--surface) 70%, transparent);
        }
        .properties-title {
          margin: 0 0 0.55em;
          font-size: 0.72em;
          font-weight: 600;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted);
        }
        .properties dl { margin: 0; display: grid; grid-template-columns: 8.5em 1fr; gap: 0.35em 0.8em; }
        .properties dt { color: var(--muted); font-size: 0.85em; }
        .properties dd { margin: 0; font-size: 0.9em; }
        .tag {
          display: inline-block;
          margin: 0 0.3em 0.3em 0;
          padding: 0.1em 0.55em;
          border-radius: 999px;
          background: color-mix(in srgb, var(--accent) 16%, transparent);
          color: var(--accent);
          font-size: 0.82em;
        }
        @page { size: auto; margin: 18mm 16mm; }
        @media print {
          :root { color-scheme: light; }
          body {
            padding: 0;
            background: #fff;
            color: #111;
            font-size: 11.5pt;
          }
          main { max-width: none; }
          h1, h2, h3, h4, h5, h6 { break-after: avoid; }
          pre, table, blockquote, .properties, .mermaid { break-inside: avoid; }
          a { color: #1c1c1e; text-decoration: underline; }
          code, pre, th { background: #f4f4f5; }
          .tag { background: #f0f0f2; color: #333; }
        }
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
        var output = ""
        if let frontmatter = parsed.frontmatter, !frontmatter.fields.isEmpty {
            output += renderProperties(frontmatter)
            output += "\n"
        }
        output += render(blocks: parsed.blocks, references: parsed.references)
        return output
    }

    /// Rendered body wrapped in a theme marker, for callers that embed the export
    /// into their own page and want the preview palette applied via CSS variables.
    static func export(body markdown: String, using theme: PreviewTheme = .system) -> String {
        """
        <div class="iris-export theme-\(theme.rawValue)">
        \(body(from: markdown))
        </div>
        """
    }

    /// CSS custom properties for a preview theme.
    ///
    /// `.system` follows the reader's light/dark appearance through
    /// `prefers-color-scheme`; the named themes pin `color-scheme` so the page
    /// always renders with the palette chosen in Settings.
    private static func paletteCSS(for theme: PreviewTheme) -> String {
        if theme == .system {
            return """
            :root {
              color-scheme: light dark;
              --text: #1c1c1e;
              --muted: #6c6c70;
              --background: #ffffff;
              --surface: #f2f2f7;
              --border: #d1d1d6;
              --accent: #6c5ce7;
              --is-dark: 0;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                color-scheme: dark;
                --text: #f2f2f7;
                --muted: #a1a1a6;
                --background: #1c1c1e;
                --surface: #2c2c2e;
                --border: #3a3a3c;
                --accent: #a29bfe;
                --is-dark: 1;
              }
            }
            """
        }

        let palette: (text: String, muted: String, background: String, surface: String, border: String, accent: String)
        switch theme {
        case .paper:
            palette = ("#1c1c1f", "#6b6b70", "#fcfbf7", "#f0eee5", "#d1cfc7", "#6c5ce7")
        case .sepia:
            palette = ("#3d3120", "#70604a", "#f5eada", "#e6d8bf", "#c7b897", "#8a5a2b")
        case .midnight:
            palette = ("#dbdff0", "#94a0b8", "#1a1c26", "#292c3b", "#3d4257", "#a29bfe")
        case .system:
            palette = ("#1c1c1e", "#6c6c70", "#ffffff", "#f2f2f7", "#d1d1d6", "#6c5ce7")
        }

        let scheme = theme.isDark ? "dark" : "light"
        let isDark = theme.isDark ? "1" : "0"
        return """
        :root {
          color-scheme: \(scheme);
          --text: \(palette.text);
          --muted: \(palette.muted);
          --background: \(palette.background);
          --surface: \(palette.surface);
          --border: \(palette.border);
          --accent: \(palette.accent);
          --is-dark: \(isDark);
        }
        """
    }

    /// Frontmatter as a readable card. The raw YAML is never emitted, matching the
    /// in-app preview so exported documents do not leak `---` fences and key/value lines.
    private static func renderProperties(_ frontmatter: MarkdownFrontmatter) -> String {
        var rows = ""
        for field in frontmatter.fields {
            let value: String
            switch field.kind {
            case .tags:
                value = field.listValues
                    .map { "<span class=\"tag\">#\(escape($0))</span>" }
                    .joined(separator: " ")
            case .list:
                value = escape(field.listValues.joined(separator: ", "))
            case .empty:
                value = "—"
            default:
                value = escape(field.value)
            }
            rows += "<dt>\(escape(field.displayKey))</dt><dd>\(value)</dd>\n"
        }
        return """
        <aside class="properties">
        <p class="properties-title">Properties</p>
        <dl>
        \(rows)</dl>
        </aside>
        """
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
            if let latex = displayMath(text) {
                return "<div class=\"math-block\">\(escape(LaTeXMathRenderer.render(latex)))</div>"
            }
            return "<p>\(renderInline(text, references: references))</p>"

        case .blockQuote(let blocks):
            if let callout = MarkdownCallout.parse(blocks) {
                let name = callout.kind.rawValue
                let foldClass = callout.isFoldable ? " callout-foldable" : ""
                let collapsed = callout.isCollapsed ? " collapsed" : ""
                let caret = callout.isFoldable
                    ? "<span class=\"callout-caret\">\(callout.isCollapsed ? "&#9656;" : "&#9662;")</span>"
                    : ""
                return """
                <details class="callout callout-\(name)\(foldClass)\(collapsed)"\(callout.isCollapsed ? "" : " open")>
                <summary>\(caret)<span class=\"callout-title\">\(renderInline(callout.title, references: references))</span></summary>
                <div class=\"callout-body\">
                \(render(blocks: callout.body, references: references))
                </div>
                </details>
                """
            }
            return "<blockquote>\n\(render(blocks: blocks, references: references))\n</blockquote>"

        case .codeBlock(let language, let lines):
            let code = lines.joined(separator: "\n")
            if language?.lowercased() == "mermaid",
               let flowchart = MermaidParser.flowchart(code) {
                return "<div class=\"mermaid\">\n\(MermaidParser.svg(flowchart))\n</div>"
            }
            let classAttribute = language.map {
                " class=\"language-\(escapeAttribute($0))\""
            } ?? ""
            let highlighted = CodeSyntaxHighlighter.htmlSpans(in: code, language: language)
            return "<pre><code\(classAttribute)>\(highlighted)</code></pre>"

        case .list(let ordered, let start, let items):
            let tag = ordered ? "ol" : "ul"
            let startAttribute = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let containsTask = items.contains { taskInfo($0) != nil }
            let listClass = containsTask ? " class=\"task-list\"" : ""
            let renderedItems = items.map { item -> String in
                if let task = taskInfo(item) {
                    let nested = render(
                        blocks: Array(item.blocks.dropFirst()),
                        references: references
                    )
                    let checkbox = task.checked ? " checked" : ""
                    return "<li class=\"task\"><input type=\"checkbox\"\(checkbox) disabled> \(renderInline(task.text, references: references))\(nested.isEmpty ? "" : "\n" + nested)</li>"
                }
                return "<li>\n\(render(blocks: item.blocks, references: references))\n</li>"
            }.joined(separator: "\n")
            return "<\(tag)\(startAttribute)\(listClass)>\n\(renderedItems)\n</\(tag)>"

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
            return renderText(value)

        case .emphasis(let children):
            return "<em>\(renderInline(children, references: references))</em>"

        case .strong(let children):
            return "<strong>\(renderInline(children, references: references))</strong>"

        case .strikethrough(let children):
            return "<del>\(renderInline(children, references: references))</del>"

        case .highlight(let children):
            return "<mark>\(renderInline(children, references: references))</mark>"

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

    private struct ExportedTask {
        let checked: Bool
        let text: String
    }

    private static func displayMath(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
            return String(trimmed.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("\\["), trimmed.hasSuffix("\\]"), trimmed.count > 4 {
            return String(trimmed.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func taskInfo(_ item: MarkdownListItem) -> ExportedTask? {
        guard case .paragraph(let raw)? = item.blocks.first else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"^\[([ xX])\][ \t]+(.+)$"#,
            options: [.dotMatchesLineSeparators]
        ),
        let match = regex.firstMatch(
            in: trimmed,
            range: NSRange(location: 0, length: (trimmed as NSString).length)
        ),
        let markerRange = Range(match.range(at: 1), in: trimmed),
        let textRange = Range(match.range(at: 2), in: trimmed) else {
            return nil
        }
        return ExportedTask(
            checked: String(trimmed[markerRange]).lowercased() == "x",
            text: String(trimmed[textRange])
        )
    }

    /// Escapes plain text while rendering inline `$…$` math as Unicode serif spans.
    private static func renderText(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\\)\$([^$\n]+)\$"#) else {
            return escape(value)
        }
        let ns = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return escape(value) }

        var output = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += escape(ns.substring(
                    with: NSRange(location: cursor, length: match.range.location - cursor)
                ))
            }
            let latex = ns.substring(with: match.range(at: 1))
            output += "<span class=\"math-inline\">\(escape(LaTeXMathRenderer.render(latex)))</span>"
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            output += escape(ns.substring(from: cursor))
        }
        return output
    }

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
