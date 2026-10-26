import AppKit
import SwiftUI

/// A native-feeling tab strip sitting above the editor card.
///
/// Each tab shows its document name, a dirty dot, and a close button on hover. The active
/// tab sits on a Liquid Glass pill so it reads as the frontmost surface.
struct TabBarView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var hoverModel = TabBarHoverModel()

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabItem(index: index, tab: tab)
                    }
                }
                .padding(.horizontal, 8)
            }

            Button {
                appState.newDocument()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help("New Tab (⌘N)")
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .frame(height: 30)
    }

    @ViewBuilder
    private func tabItem(index: Int, tab: EditorDocument) -> some View {
        let isActive = index == appState.currentTabIndex

        HStack(spacing: 6) {
            Text(tab.displayName)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            if tab.isDirty {
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 6, height: 6)
            }

            if hoverModel.hoveredTab == tab.id || isActive {
                Button {
                    appState.closeTab(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close “\(tab.displayName)”")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isActive {
                GlassBackdrop(style: .regular, cornerRadius: 8, interactive: true)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            appState.selectTab(at: index)
        }
        .onHover { inside in
            if inside {
                hoverModel.hoveredTab = tab.id
            } else if hoverModel.hoveredTab == tab.id {
                hoverModel.hoveredTab = nil
            }
        }
        .contextMenu {
            Button("Close") {
                appState.closeTab(at: index)
            }
            if tab.fileURL != nil {
                Button("Reveal in Finder") {
                    if let url = tab.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
    }
}

/// Hover tracking for the tab strip, kept out of SwiftUI `@State` so the
/// macro-less Command Line Tools build path works.
@MainActor
final class TabBarHoverModel: ObservableObject {
    @Published var hoveredTab: UUID?
}
