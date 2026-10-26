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

    var body: some View {
        let document = MarkdownBlockParser.parseDocument(markdown)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
            GlassBackdrop(style: .regular, cornerRadius: 0)
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let references: [String: MarkdownLinkReference]
    var baseURL: URL? = nil

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
            codeSurface(lines: lines, label: language)

        case .list(let ordered, let start, let items):
            list(ordered: ordered, start: start, items: items)

        case .table(let header, let alignments, let rows):
            MarkdownTablePreview(
                header: header,
                alignments: alignments,
                rows: rows,
                references: references
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

        if let image = standaloneImage(in: inlines) {
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

    private func list(
        ordered: Bool,
        start: Int,
        items: [MarkdownListItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
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
    }

    private func codeSurface(lines: [String], label: String?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 2)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 12.5, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        )
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

// MARK: - Inline text

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
                var run = AttributedString(value)
                applyPresentation(&run, bold: bold, italic: italic, strikethrough: strikethrough)
                result.append(run)

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
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let baseURL {
            return URL(
                fileURLWithPath: trimmed.removingPercentEncoding ?? trimmed,
                relativeTo: baseURL
            ).standardizedFileURL
        }
        return URL(string: trimmed)
    }

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
        MarkdownInlineText(references: references, baseURL: nil, size: 13)
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
