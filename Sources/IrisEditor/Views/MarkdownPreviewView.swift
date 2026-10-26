import AppKit
import SwiftUI

/// Renders the current Markdown document block-by-block.
///
/// Headings, lists, quotes, fenced code, and rules are laid out as native SwiftUI blocks;
/// the text *inside* each block is styled with `AttributedString(markdown:)` using the
/// inline-only syntax, so bold/italic/code spans render everywhere without a web view.
struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(MarkdownBlockParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
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

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 6 : 0)

        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .blockQuote(let lines):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if !line.isEmpty {
                        inlineText(line)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

        case .codeBlock(_, let lines):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12.5, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            )

        case .table(let header, let alignments, let rows):
            MarkdownTablePreview(header: header, alignments: alignments, rows: rows)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        inlineText(item)
                            .font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(item.number).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        inlineText(item.text)
                            .font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func inlineText(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
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
}

/// Renders a parsed GFM pipe table with per-column alignment and inline Markdown cells.
private struct MarkdownTablePreview: View {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]

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
        inlineText(text)
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

    private func inlineText(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }
}
