import SwiftUI

/// Native "Properties" card that replaces raw YAML frontmatter in the preview.
///
/// The card keeps the metadata readable (tags become capsules, dates and numbers keep
/// their type) and sits on a Liquid Glass surface that matches the rest of the editor.
struct MarkdownPropertiesCard: View {
    let frontmatter: MarkdownFrontmatter
    var onOpenTag: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.properties)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(visibleFields.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(L10n.propertyCount(visibleFields.count))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleFields) { field in
                    HStack(alignment: .top, spacing: 10) {
                        Text(field.displayKey)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                            .lineLimit(1)

                        fieldValue(field)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 10, interactive: true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.documentProperties)
        .accessibilityIdentifier("Preview.PropertiesCard")
    }

    private var visibleFields: [MarkdownFrontmatterField] {
        frontmatter.fields.filter { !$0.key.isEmpty }
    }

    @ViewBuilder
    private func fieldValue(_ field: MarkdownFrontmatterField) -> some View {
        switch field.kind {
        case .empty:
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

        case .tags:
            FlowLayout(spacing: 5) {
                ForEach(Array(field.listValues.enumerated()), id: \.offset) { _, tag in
                    tagChip(tag)
                }
            }

        case .list:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(field.listValues.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(item)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                    }
                }
            }

        case .boolean:
            HStack(spacing: 5) {
                Image(systemName: field.value.lowercased() == "true"
                      ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(field.value.lowercased() == "true" ? .green : .secondary)
                Text(field.value)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        case .date, .number:
            Text(field.value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

        case .text:
            Text(field.value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tagChip(_ tag: String) -> some View {
        Button {
            onOpenTag?(tag)
        } label: {
            Text("#\(tag)")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.14))
                )
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.filterByTag(tag))
        .accessibilityIdentifier("Preview.Tag.\(tag)")
    }
}

/// A minimal wrapping layout for tag chips. `Layout` keeps rows compact without needing
/// a fixed column count, matching how properties read in Obsidian.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: proposal.width ?? rowWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
