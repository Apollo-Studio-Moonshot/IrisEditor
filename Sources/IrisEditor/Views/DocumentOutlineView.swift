import AppKit
import SwiftUI

/// Obsidian-style document outline: a sidebar panel that shows the Markdown heading
/// hierarchy and lets users click to jump to the corresponding line in the editor.
struct DocumentOutlineView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = OutlineModel()
    @StateObject private var hoverModel = OutlineHoverModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if model.headings.isEmpty {
                emptyState
            } else {
                headingList
            }
        }
        .frame(width: 230)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 0, interactive: true)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(width: 0.5)
        }
        .onAppear {
            model.refresh(text: appState.document.text)
        }
        .onChange(of: appState.document.id) { _, _ in
            model.refresh(text: appState.document.text)
        }
        .onChange(of: appState.document.text) { _, newText in
            model.refresh(text: newText)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Outline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                appState.toggleOutline()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Close Outline (⇧⌘O)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 20))
                .foregroundStyle(.quaternary)
            Text("No headings yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("Add a # heading to see it here.")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var headingList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.headings) { heading in
                        headingRow(heading)
                            .id(heading.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: activeHeadingID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func headingRow(_ heading: MarkdownOutline.Heading) -> some View {
        let isHovered = hoverModel.hoveredHeading == heading.id
        let isActive = activeHeadingID == heading.id

        return Button {
            appState.reveal(line: heading.line)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: headingIcon(heading.level))
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 14, alignment: .leading)

                Text(heading.title)
                    .font(.system(size: 12, weight: heading.level == 1 ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Text("L\(heading.line)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.leading, CGFloat((heading.level - 1) * 12))
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(background(isHovered: isHovered, isActive: isActive))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoverModel.hoveredHeading = heading.id
            } else if hoverModel.hoveredHeading == heading.id {
                hoverModel.hoveredHeading = nil
            }
        }
        .help("Go to line \(heading.line)")
    }

    private func background(isHovered: Bool, isActive: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.14)
        }
        if isHovered {
            return Color(nsColor: .quaternaryLabelColor).opacity(0.4)
        }
        return .clear
    }

    /// The deepest heading at or above the cursor, so the sidebar follows the editor.
    private var activeHeadingID: String? {
        model.headings.last(where: { $0.line <= appState.cursorLine })?.id
    }

    private func headingIcon(_ level: Int) -> String {
        switch level {
        case 1: return "textformat.size.larger"
        case 2: return "textformat.size"
        case 3: return "textformat.size.smaller"
        default: return "textformat"
        }
    }
}

@MainActor
final class OutlineModel: ObservableObject {
    @Published var headings: [MarkdownOutline.Heading] = []

    func refresh(text: String) {
        let updated = MarkdownOutline.headings(in: text)
        guard updated != headings else { return }
        headings = updated
    }
}

@MainActor
final class OutlineHoverModel: ObservableObject {
    @Published var hoveredHeading: String?
}
