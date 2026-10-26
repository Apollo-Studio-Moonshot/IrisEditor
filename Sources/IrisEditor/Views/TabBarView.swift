import AppKit
import SwiftUI

/// A native-feeling tab strip sitting above the editor card.
///
/// Each tab shows its document name, a dirty dot, and a close button on hover. The active
/// tab sits on a Liquid Glass pill that slides between tabs as selection changes.
struct TabBarView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var hoverModel = TabBarHoverModel()
    @Namespace private var activePill

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabItemView(
                                tab: tab,
                                index: index,
                                isActive: index == appState.currentTabIndex,
                                namespace: activePill,
                                hoverModel: hoverModel
                            )
                            .id(tab.id)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.84, anchor: .bottomLeading)
                                        .combined(with: .opacity)
                                        .combined(with: .offset(x: -10)),
                                    removal: .scale(scale: 0.84, anchor: .bottomLeading)
                                        .combined(with: .opacity)
                                        .combined(with: .offset(x: 10))
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .animation(.snappy(duration: 0.28, extraBounce: 0.06), value: appState.tabs.map(\.id))
                }
                .onChange(of: appState.currentTabIndex) { _, index in
                    guard appState.tabs.indices.contains(index) else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(appState.tabs[index].id, anchor: .center)
                    }
                }
                .onChange(of: appState.tabs.count) { _, _ in
                    guard appState.tabs.indices.contains(appState.currentTabIndex) else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(appState.tabs[appState.currentTabIndex].id, anchor: .center)
                    }
                }
            }

            Button {
                appState.newDocument()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help("New Tab (⌘T)")
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .frame(height: 32)
    }
}

private struct TabItemView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var tab: EditorDocument
    let index: Int
    let isActive: Bool
    let namespace: Namespace.ID
    @ObservedObject var hoverModel: TabBarHoverModel

    private var isHovered: Bool {
        hoverModel.hoveredTab == tab.id
    }

    private var showsCloseButton: Bool {
        isActive || isHovered
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 190)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            if tab.isDirty {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.75))
                    .frame(width: 6, height: 6)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                    .help("Unsaved changes")
            }

            if showsCloseButton {
                Button {
                    appState.closeTab(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .background {
                            Circle()
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(isHovered ? 0.8 : 0))
                        }
                }
                .buttonStyle(.borderless)
                .help("Close “\(tab.displayName)”")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isActive {
                GlassBackdrop(style: .regular, cornerRadius: 8, interactive: true)
                    .matchedGeometryEffect(id: "active-tab-pill", in: namespace)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(isHovered ? 0.55 : 0.3))
            }
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
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
        .scaleEffect(isHovered && !isActive ? 1.015 : 1)
        .animation(.snappy(duration: 0.16), value: isHovered)
        .animation(.snappy(duration: 0.2), value: showsCloseButton)
        .animation(.snappy(duration: 0.2), value: tab.isDirty)
        .help(tab.fileURL?.path ?? tab.displayName)
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

            Button("Copy Path") {
                if let url = tab.fileURL {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
            .disabled(tab.fileURL == nil)
        }
    }
}

/// Hover tracking for the tab strip, kept out of SwiftUI `@State` so the
/// macro-less Command Line Tools build path works.
@MainActor
final class TabBarHoverModel: ObservableObject {
    @Published var hoveredTab: UUID?
}
