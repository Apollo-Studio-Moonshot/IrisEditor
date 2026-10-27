import AppKit
import SwiftUI

/// Renders the current Markdown document block-by-block.
///
/// The block parser handles containers; inline spans are resolved by `MarkdownInlineParser`
/// and painted as a native `Text` (bold/italic, code, links, breaks) so the preview covers
/// the full Markdown Guide basic syntax without a web view.
struct MarkdownPreviewView: View {
    let markdown: String
    var baseURL: URL? = nil
    var theme: PreviewTheme = .system
    var onToggleTask: (@MainActor @Sendable (String) -> Void)? = nil

    var body: some View {
        let document = MarkdownBlockParser.parseDocument(markdown)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let frontmatter = document.frontmatter, !frontmatter.fields.isEmpty {
                    MarkdownPropertiesCard(frontmatter: frontmatter)
                        .padding(.bottom, 4)
                }

                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(
                        block: block,
                        references: document.references,
                        baseURL: baseURL
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background {
            ZStack {
                theme.background
                GlassBackdrop(style: .regular, cornerRadius: 0)
                    .opacity(theme == .system ? 1 : 0.35)
            }
        }
        .foregroundStyle(theme.text)
        .environment(\.previewTheme, theme)
        .environment(\.togglePreviewTask, onToggleTask)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

// MARK: - Preview environment

private struct PreviewThemeKey: EnvironmentKey {
    static let defaultValue: PreviewTheme = .system
}

private struct TogglePreviewTaskKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (String) -> Void)? = nil
}

extension EnvironmentValues {
    fileprivate var previewTheme: PreviewTheme {
        get { self[PreviewThemeKey.self] }
        set { self[PreviewThemeKey.self] = newValue }
    }

    fileprivate var togglePreviewTask: (@MainActor @Sendable (String) -> Void)? {
        get { self[TogglePreviewTaskKey.self] }
        set { self[TogglePreviewTaskKey.self] = newValue }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let references: [String: MarkdownLinkReference]
    var baseURL: URL? = nil

    @Environment(\.previewTheme) private var theme
    @Environment(\.togglePreviewTask) private var onToggleTask

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inline(size: headingSize(level)).text(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 6 : 0)

        case .paragraph(let text):
            paragraph(text)

        case .blockQuote(let blocks):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(
                        block: child,
                        references: references,
                        baseURL: baseURL
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
            }

        case .codeBlock(let language, let lines):
            if language?.lowercased() == "mermaid" {
                MermaidBlockView(source: lines.joined(separator: "\n"))
            } else {
                codeSurface(lines: lines, label: language)
            }

        case .list(let ordered, let start, let items):
            list(ordered: ordered, start: start, items: items)

        case .table(let header, let alignments, let rows):
            MarkdownTablePreview(
                header: header,
                alignments: alignments,
                rows: rows,
                references: references,
                baseURL: baseURL
            )

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)

        case .htmlBlock(let lines):
            codeSurface(lines: lines, label: "HTML")
        }
    }

    @ViewBuilder
    private func paragraph(_ text: String) -> some View {
        let inlines = MarkdownInlineParser(references: references).parse(text)

        if let latex = displayMath(text) {
            mathBlock(latex)
        } else if let image = standaloneImage(in: inlines) {
            MarkdownImageView(
                source: image.source,
                alt: image.alt,
                title: image.title,
                link: image.link,
                baseURL: baseURL
            )
        } else {
            inline(size: 14).text(inlines)
                .font(.system(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Recognizes `$$ … $$` and `\\[ … \\]` paragraphs as display math.
    private func displayMath(_ text: String) -> String? {
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

    private func mathBlock(_ latex: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(LaTeXMathRenderer.render(latex))
                .font(.system(size: 17, design: .serif))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.surface.opacity(0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.border.opacity(0.6), lineWidth: 0.5)
        }
    }

    private func list(
        ordered: Bool,
        start: Int,
        items: [MarkdownListItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                listItem(item, ordered: ordered, index: index, start: start)
            }
        }
    }

    @ViewBuilder
    private func listItem(
        _ item: MarkdownListItem,
        ordered: Bool,
        index: Int,
        start: Int
    ) -> some View {
        if let task = taskInfo(item) {
            Button {
                onToggleTask?(task.text)
            } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: task.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(task.checked ? Color.accentColor : Color.secondary)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 6) {
                        inline(size: 14)
                            .text(MarkdownInlineParser(references: references).parse(task.text))
                            .font(.system(size: 14))
                            .strikethrough(task.checked, color: .secondary)
                            .foregroundStyle(task.checked ? Color.secondary : Color.primary)

                        ForEach(Array(item.blocks.dropFirst().enumerated()), id: \.offset) { _, child in
                            MarkdownBlockView(
                                block: child,
                                references: references,
                                baseURL: baseURL
                            )
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.text)
            .accessibilityValue(task.checked ? "Completed" : "Not completed")
        } else {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if ordered {
                        Text("\(start + index).")
                            .monospacedDigit()
                    } else {
                        Text("•")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(minWidth: ordered ? 18 : 10, alignment: .trailing)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(
                            block: child,
                            references: references,
                            baseURL: baseURL
                        )
                    }
                }
            }
        }
    }

    private struct TaskInfo {
        let checked: Bool
        let text: String
    }

    private func taskInfo(_ item: MarkdownListItem) -> TaskInfo? {
        guard case .paragraph(let raw)? = item.blocks.first else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^\[([ xX])\][ \t]+(.+)$"#, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)),
              let markerRange = Range(match.range(at: 1), in: trimmed),
              let textRange = Range(match.range(at: 2), in: trimmed) else {
            return nil
        }
        let marker = String(trimmed[markerRange])
        return TaskInfo(
            checked: marker.lowercased() == "x",
            text: String(trimmed[textRange])
        )
    }

    private func codeSurface(lines: [String], label: String?) -> some View {
        let code = lines.joined(separator: "\n")
        let language = label?.lowercased()

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 2)
                }
                Text(highlightedCode(code, language: language))
                    .font(.system(size: 12.5, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.surface.opacity(0.7))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.border.opacity(0.5), lineWidth: 0.5)
        }
    }

    private func highlightedCode(_ code: String, language: String?) -> AttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor(theme.text),
        ]
        let attributed = NSMutableAttributedString(string: code, attributes: baseAttributes)

        for token in CodeSyntaxHighlighter.tokens(in: code, language: language) {
            guard NSMaxRange(token.range) <= attributed.length else { continue }
            attributed.addAttribute(
                .foregroundColor,
                value: color(for: token.kind),
                range: token.range
            )
        }
        return AttributedString(attributed)
    }

    private func color(for kind: CodeSyntaxHighlighter.TokenKind) -> NSColor {
        switch kind {
        case .keyword: return .systemPink
        case .string: return .systemRed
        case .comment: return .tertiaryLabelColor
        case .number: return .systemBlue
        case .type: return .systemTeal
        case .function: return .systemPurple
        case .property: return .systemOrange
        case .punctuation, .plain: return NSColor(theme.text)
        }
    }

    private func inline(size: CGFloat) -> MarkdownInlineText {
        MarkdownInlineText(references: references, baseURL: baseURL, size: size)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 26
        case 2: return 22
        case 3: return 19
        case 4: return 16
        case 5: return 14
        default: return 13
        }
    }

    // MARK: - Standalone images

    private struct StandaloneImage {
        let source: String
        let alt: String
        let title: String?
        let link: String?
    }

    private func standaloneImage(in inlines: [MarkdownInline]) -> StandaloneImage? {
        let visible = inlines.filter { inline in
            switch inline {
            case .text(let value):
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .softBreak, .hardBreak:
                return false
            default:
                return true
            }
        }

        guard visible.count == 1, let only = visible.first else { return nil }

        switch only {
        case .image(let source, let alt, let title):
            return StandaloneImage(source: source, alt: alt, title: title, link: nil)

        case .link(let destination, _, let children):
            let visibleChildren = children.filter { inline in
                if case .text(let value) = inline {
                    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return true
            }
            guard visibleChildren.count == 1,
                  case .image(let source, let alt, let title) = visibleChildren[0] else {
                return nil
            }
            return StandaloneImage(source: source, alt: alt, title: title, link: destination)

        default:
            return nil
        }
    }
}

// MARK: - Mermaid

/// Renders a small `flowchart TD/LR` graph with a native Canvas. Unsupported diagrams fall
/// back to a clearly labelled code surface rather than showing raw Mermaid syntax unmarked.
private struct MermaidBlockView: View {
    let source: String
    @Environment(\.previewTheme) private var theme

    var body: some View {
        if let chart = MermaidParser.flowchart(source) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Mermaid", systemImage: "chart.bar.doc.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                MermaidDiagramView(chart: chart)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Mermaid (preview simplified — diagram not recognized)",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(source)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.surface.opacity(0.7))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.border.opacity(0.5), lineWidth: 0.5)
            }
        }
    }
}

private struct MermaidDiagramView: View {
    let chart: MermaidParser.Flowchart
    @Environment(\.previewTheme) private var theme

    private let nodeWidth: CGFloat = 132
    private let nodeHeight: CGFloat = 30
    private let columnGap: CGFloat = 34
    private let rowGap: CGFloat = 58
    private let padding: CGFloat = 22

    var body: some View {
        let levels = computeLevels()
        let maxPerLevel = levels.values.map(\.count).max() ?? 1
        let levelCount = max(1, (levels.keys.max() ?? 0) + 1)
        let isHorizontal = chart.direction == .leftRight

        let width = isHorizontal
            ? CGFloat(levelCount) * (nodeWidth + columnGap) + padding * 2
            : CGFloat(maxPerLevel) * (nodeWidth + columnGap) + padding * 2
        let height = isHorizontal
            ? CGFloat(maxPerLevel) * (nodeHeight + rowGap) + padding * 2
            : CGFloat(levelCount) * (nodeHeight + rowGap) + padding * 2

        let positions = computePositions(
            levels: levels,
            maxPerLevel: maxPerLevel,
            levelCount: levelCount,
            isHorizontal: isHorizontal,
            width: width,
            height: height
        )

        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            Canvas { context, _ in
                for edge in chart.edges {
                    guard let from = positions[edge.from], let to = positions[edge.to] else {
                        continue
                    }
                    drawEdge(edge, from: from, to: to, in: &context)
                }

                for node in chart.nodes {
                    guard let point = positions[node.id] else { continue }
                    let rect = CGRect(
                        x: point.x - nodeWidth / 2,
                        y: point.y - nodeHeight / 2,
                        width: nodeWidth,
                        height: nodeHeight
                    )
                    let shape = Path(roundedRect: rect, cornerRadius: 7)
                    context.fill(shape, with: .color(theme.surface))
                    context.stroke(shape, with: .color(theme.border), lineWidth: 0.8)
                    context.draw(
                        Text(node.label.isEmpty ? node.id : node.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.text),
                        at: point
                    )
                }
            }
            .frame(width: width, height: height)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.surface.opacity(0.35))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.border.opacity(0.45), lineWidth: 0.5)
        }
    }

    private func drawEdge(
        _ edge: MermaidParser.Flowchart.Edge,
        from: CGPoint,
        to: CGPoint,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(
            path,
            with: .color(.secondary.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)
        )

        // Arrowhead
        let angle = atan2(to.y - from.y, to.x - from.x)
        let tip = to
        let size: CGFloat = 6
        var arrow = Path()
        arrow.move(to: CGPoint(
            x: tip.x - size * cos(angle - .pi / 7),
            y: tip.y - size * sin(angle - .pi / 7)
        ))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(
            x: tip.x - size * cos(angle + .pi / 7),
            y: tip.y - size * sin(angle + .pi / 7)
        ))
        context.fill(arrow, with: .color(.secondary.opacity(0.7)))

        if !edge.label.isEmpty {
            context.draw(
                Text(edge.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 8)
            )
        }
    }

    private func computeLevels() -> [Int: [String]] {
        var adjacency: [String: [String]] = [:]
        var indegree: [String: Int] = [:]
        for node in chart.nodes {
            adjacency[node.id] = []
            indegree[node.id] = 0
        }
        for edge in chart.edges {
            adjacency[edge.from, default: []].append(edge.to)
            indegree[edge.to, default: 0] += 1
        }

        var level: [String: Int] = [:]
        var queue: [String] = chart.nodes
            .filter { (indegree[$0.id] ?? 0) == 0 }
            .map(\.id)
        if queue.isEmpty, let first = chart.nodes.first {
            queue = [first.id]
        }
        for id in queue { level[id] = 0 }

        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for next in adjacency[current] ?? [] {
                let candidate = (level[current] ?? 0) + 1
                if candidate > (level[next] ?? -1) {
                    level[next] = candidate
                    queue.append(next)
                }
            }
        }
        for node in chart.nodes where level[node.id] == nil {
            level[node.id] = 0
        }

        var grouped: [Int: [String]] = [:]
        for node in chart.nodes {
            grouped[level[node.id] ?? 0, default: []].append(node.id)
        }
        return grouped
    }

    private func computePositions(
        levels: [Int: [String]],
        maxPerLevel: Int,
        levelCount: Int,
        isHorizontal: Bool,
        width: CGFloat,
        height: CGFloat
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]

        for (levelIndex, ids) in levels {
            for (index, id) in ids.enumerated() {
                let alongLevel = CGFloat(index) - CGFloat(ids.count - 1) / 2
                if isHorizontal {
                    let x = padding + nodeWidth / 2 + CGFloat(levelIndex) * (nodeWidth + columnGap)
                    let y = height / 2 + alongLevel * (nodeHeight + rowGap)
                    positions[id] = CGPoint(x: x, y: y)
                } else {
                    let y = padding + nodeHeight / 2 + CGFloat(levelIndex) * (nodeHeight + rowGap)
                    let x = width / 2 + alongLevel * (nodeWidth + columnGap)
                    positions[id] = CGPoint(x: x, y: y)
                }
            }
        }
        return positions
    }
}


/// Builds a native `AttributedString` from parsed inline spans.
private struct MarkdownInlineText {
    let references: [String: MarkdownLinkReference]
    let baseURL: URL?
    let size: CGFloat

    func text(_ raw: String) -> Text {
        Text(attributed(MarkdownInlineParser(references: references).parse(raw)))
    }

    func text(_ inlines: [MarkdownInline]) -> Text {
        Text(attributed(inlines))
    }

    private func attributed(_ inlines: [MarkdownInline]) -> AttributedString {
        var result = AttributedString()
        append(inlines, to: &result, bold: false, italic: false, strikethrough: false)
        return result
    }

    private func append(
        _ inlines: [MarkdownInline],
        to result: inout AttributedString,
        bold: Bool,
        italic: Bool,
        strikethrough: Bool
    ) {
        for inline in inlines {
            switch inline {
            case .text(let value):
                appendText(
                    value,
                    to: &result,
                    bold: bold,
                    italic: italic,
                    strikethrough: strikethrough
                )

            case .emphasis(let children):
                append(
                    children,
                    to: &result,
                    bold: bold,
                    italic: true,
                    strikethrough: strikethrough
                )

            case .strong(let children):
                append(
                    children,
                    to: &result,
                    bold: true,
                    italic: italic,
                    strikethrough: strikethrough
                )

            case .strikethrough(let children):
                append(
                    children,
                    to: &result,
                    bold: bold,
                    italic: italic,
                    strikethrough: true
                )

            case .code(let value):
                var run = AttributedString(value)
                run.font = .system(size: max(9, size - 1.5), design: .monospaced)
                run.foregroundColor = .secondary
                result.append(run)

            case .link(let destination, _, let children):
                var nested = AttributedString()
                append(
                    children,
                    to: &nested,
                    bold: bold,
                    italic: italic,
                    strikethrough: strikethrough
                )
                if let url = resolve(destination) {
                    nested.link = url
                }
                result.append(nested)

            case .image(_, let alt, _):
                var run = AttributedString(alt.isEmpty ? "Image" : alt)
                run.foregroundColor = .secondary
                result.append(run)

            case .wikiLink(let target, let label):
                var run = AttributedString(label)
                run.foregroundColor = .accentColor
                if let url = wikiURL(for: target) {
                    run.link = url
                }
                result.append(run)

            case .softBreak:
                result.append(AttributedString(" "))

            case .hardBreak:
                result.append(AttributedString("\n"))

            case .html(let value):
                var run = AttributedString(value)
                run.font = .system(size: max(9, size - 1.5), design: .monospaced)
                run.foregroundColor = .secondary
                result.append(run)
            }
        }
    }

    /// Appends plain text while rendering inline `$…$` math as Unicode serif runs.
    private func appendText(
        _ value: String,
        to result: inout AttributedString,
        bold: Bool,
        italic: Bool,
        strikethrough: Bool
    ) {
        let pattern = try? NSRegularExpression(pattern: #"(?<!\\)\$([^$\n]+)\$"#)
        let ns = value as NSString
        let matches = pattern?.matches(
            in: value,
            range: NSRange(location: 0, length: ns.length)
        ) ?? []

        guard !matches.isEmpty else {
            var run = AttributedString(value)
            applyPresentation(&run, bold: bold, italic: italic, strikethrough: strikethrough)
            result.append(run)
            return
        }

        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let plain = ns.substring(
                    with: NSRange(location: cursor, length: match.range.location - cursor)
                )
                var run = AttributedString(plain)
                applyPresentation(&run, bold: bold, italic: italic, strikethrough: strikethrough)
                result.append(run)
            }

            let latex = ns.substring(with: match.range(at: 1))
            var math = AttributedString(LaTeXMathRenderer.render(latex))
            math.font = .system(size: size, design: .serif).italic()
            applyPresentation(&math, bold: bold, italic: true, strikethrough: strikethrough)
            result.append(math)
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            var run = AttributedString(ns.substring(from: cursor))
            applyPresentation(&run, bold: bold, italic: italic, strikethrough: strikethrough)
            result.append(run)
        }
    }

    private func applyPresentation(
        _ run: inout AttributedString,
        bold: Bool,
        italic: Bool,
        strikethrough: Bool
    ) {
        var intent: InlinePresentationIntent = []
        if bold { intent.insert(.stronglyEmphasized) }
        if italic { intent.insert(.emphasized) }
        if strikethrough { intent.insert(.strikethrough) }
        if !intent.isEmpty {
            run.inlinePresentationIntent = intent
        }
    }

    private func resolve(_ destination: String) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            // Only hand known-safe schemes to the system. Markdown files can contain
            // `javascript:`/`data:` links, which should not become clickable actions.
            return Self.allowedLinkSchemes.contains(scheme) ? url : nil
        }
        if let baseURL {
            return URL(
                fileURLWithPath: trimmed.removingPercentEncoding ?? trimmed,
                relativeTo: baseURL
            ).standardizedFileURL
        }
        return URL(string: trimmed)
    }

    private static let allowedLinkSchemes: Set<String> = [
        "http", "https", "mailto", "file", "iriseditor",
    ]

    /// Custom URL intercepted by `ContentView` to resolve `[[wiki links]]` inside Iris.
    private func wikiURL(for target: String) -> URL? {
        var components = URLComponents()
        components.scheme = "iriseditor"
        components.host = "wiki"
        components.queryItems = [URLQueryItem(name: "target", value: target)]
        return components.url
    }
}

// MARK: - Images

private struct MarkdownImageView: View {
    let source: String
    let alt: String
    let title: String?
    let link: String?
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageContent
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture {
            if let destination = link.flatMap(resolve) {
                NSWorkspace.shared.open(destination)
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let url = resolvedImageURL {
            if url.isFileURL {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                } else {
                    placeholder
                }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 420)
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                    }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text(alt.isEmpty ? "Image" : alt)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        )
    }

    private var caption: String? {
        if let title, !title.isEmpty { return title }
        return alt.isEmpty ? nil : alt
    }

    private var resolvedImageURL: URL? {
        resolve(source)
    }

    private func resolve(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "file" {
            return url
        }
        if trimmed.hasPrefix("//"), let url = URL(string: "https:" + trimmed) {
            return url
        }
        if let baseURL {
            return URL(
                fileURLWithPath: trimmed.removingPercentEncoding ?? trimmed,
                relativeTo: baseURL
            ).standardizedFileURL
        }
        return URL(fileURLWithPath: trimmed.removingPercentEncoding ?? trimmed)
    }
}

// MARK: - Tables

/// Renders a parsed GFM pipe table with per-column alignment and inline Markdown cells.
private struct MarkdownTablePreview: View {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
    let references: [String: MarkdownLinkReference]
    let baseURL: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], alignment: alignment(column), isHeader: true)
                    }
                }

                Divider()
                    .gridCellColumns(header.count)

                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            cell(rows[row][column], alignment: alignment(column), isHeader: false)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: 8))
    }

    private func alignment(_ column: Int) -> MarkdownTableAlignment {
        column < alignments.count ? alignments[column] : .left
    }

    @ViewBuilder
    private func cell(_ text: String, alignment: MarkdownTableAlignment, isHeader: Bool) -> some View {
        MarkdownInlineText(references: references, baseURL: baseURL, size: 13)
            .text(text)
            .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
            .padding(.horizontal, 10)
            .padding(.vertical, isHeader ? 7 : 5)
            .background(isHeader ? Color(nsColor: .quaternaryLabelColor).opacity(0.35) : .clear)
    }

    private func frameAlignment(_ alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
