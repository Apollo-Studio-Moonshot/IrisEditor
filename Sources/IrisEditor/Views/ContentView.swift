import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    /// 3×3 GFM pipe table inserted at the cursor.
    static let tableTemplate = """
    | Column 1 | Column 2 | Column 3 |
    | -------- | -------- | -------- |
    |          |          |          |
    |          |          |          |
    """

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabBarView()

                if appState.showFindReplace || appState.showGoToLine {
                    FindReplacePanel()
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if appState.viewMode != .preview {
                    markdownToolbar
                        .transition(.opacity)
                }

                editorCard
                StatusBarView()
            }
        }
        .background(
            WindowConfigurator(
                displayName: appState.document.displayName,
                fileURL: appState.document.fileURL,
                isDirty: appState.document.isDirty
            )
        )
        .navigationTitle(appState.document.displayName)
        .navigationSubtitle(appState.document.fileURL?.deletingLastPathComponent().path ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.newDocument()
                } label: {
                    Label("New", systemImage: "square.and.pencil")
                }
                .help("New Document (⌘N)")

                Button {
                    appState.openDocument()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open… (⌘O)")

                Button {
                    appState.saveDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save (⌘S)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.showFindReplace.toggle()
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .help("Find & Replace (⌘F)")

                Button {
                    appState.showGoToLine.toggle()
                } label: {
                    Label("Go to Line", systemImage: "arrow.up.arrow.down")
                }
                .help("Go to Line (⌘G)")

                Button {
                    appState.viewMode = appState.viewMode.next
                } label: {
                    Label("Preview", systemImage: appState.viewMode.toolbarIcon)
                }
                .help(appState.viewMode.toolbarHelp)
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .animation(.snappy(duration: 0.22), value: appState.showFindReplace)
        .animation(.snappy(duration: 0.22), value: appState.showGoToLine)
        .animation(.snappy(duration: 0.22), value: appState.viewMode)
    }

    private var editorCard: some View {
        ZStack {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            switch appState.viewMode {
            case .source:
                sourcePane
            case .preview:
                MarkdownPreviewView(
                    markdown: appState.document.text,
                    baseURL: previewBaseURL
                )
                .clipShape(.rect(cornerRadius: 13))
            case .split:
                HSplitView {
                    sourcePane
                        .frame(minWidth: 280)
                    MarkdownPreviewView(
                        markdown: appState.document.text,
                        baseURL: previewBaseURL
                    )
                    .frame(minWidth: 280)
                }
                .clipShape(.rect(cornerRadius: 13))
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var previewBaseURL: URL? {
        appState.document.fileURL?.deletingLastPathComponent()
    }

    private var sourcePane: some View {
        TextEditorViewRepresentable(
            text: Binding(
                get: { appState.document.text },
                set: { newValue in
                    guard appState.document.text != newValue else { return }
                    appState.document.text = newValue
                    appState.document.isDirty = true
                }
            ),
            settings: appState.settings
        )
        .padding(1)
        .clipShape(.rect(cornerRadius: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var markdownToolbar: some View {
        HStack(spacing: 8) {
            formatButton("H1", prefix: "# ", help: "Heading 1")
            formatButton("B", prefix: "**", help: "Bold")
            formatButton("I", prefix: "*", help: "Italic")
            formatButton("`", prefix: "`", help: "Inline Code")
            formatButton("S", prefix: "~~", help: "Strikethrough")

            Divider()
                .frame(height: 16)

            Button {
                appState.toggleMarkdownFormat(prefix: "- ")
            } label: {
                Image(systemName: "list.bullet")
            }
            .help("Bulleted List")

            Button {
                appState.toggleMarkdownFormat(prefix: "> ")
            } label: {
                Image(systemName: "text.quote")
            }
            .help("Block Quote")

            Button {
                appState.insertSnippet(Self.tableTemplate)
            } label: {
                Image(systemName: "tablecells")
            }
            .help("Insert Table")

            Spacer()
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func formatButton(_ title: String, prefix: String, help: String) -> some View {
        Button {
            appState.toggleMarkdownFormat(prefix: prefix)
        } label: {
            Text(title)
                .fontWeight(.semibold)
                .frame(minWidth: 20, minHeight: 20)
        }
        .help(help)
    }
}
