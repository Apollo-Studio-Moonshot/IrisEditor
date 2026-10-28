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
                if !appState.isZenMode {
                    TabBarView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    if appState.showOutline && !appState.isZenMode {
                        SidebarView()
                            .padding(.leading, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    VStack(spacing: 0) {
                        if (appState.showFindReplace || appState.showGoToLine) && !appState.isZenMode {
                            FindReplacePanel()
                                .padding(.top, 10)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if appState.viewMode != .preview && !appState.isZenMode {
                            markdownToolbar
                                .transition(.opacity)
                        }

                        editorCard
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !appState.isZenMode {
                    StatusBarView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .overlay {
            overlayContent
        }
        .overlay(alignment: .bottom) {
            if appState.showWikiSuggestions && !appState.showCommandPalette && !appState.showQuickSwitcher {
                WikiSuggestionBar()
                    .padding(.bottom, 42)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(appState.settings.accentColor)
        .preferredColorScheme(appState.settings.appearance.colorScheme)
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
                    Label(L10n.newButton, systemImage: "square.and.pencil")
                }
                .help(L10n.newTabHelp)
                .accessibilityLabel(L10n.newButton)
                .accessibilityIdentifier("Toolbar.New")

                Button {
                    appState.openDocument()
                } label: {
                    Label(L10n.openButton, systemImage: "folder")
                }
                .help(L10n.openHelp)
                .accessibilityLabel(L10n.openButton)
                .accessibilityIdentifier("Toolbar.Open")

                Button {
                    appState.saveDocument()
                } label: {
                    Label(L10n.saveButton, systemImage: "square.and.arrow.down")
                }
                .help(L10n.saveHelp)
                .accessibilityLabel(L10n.saveButton)
                .accessibilityIdentifier("Toolbar.Save")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.toggleQuickSwitcher()
                } label: {
                    Label(L10n.quickSwitcherButton, systemImage: "rectangle.stack")
                }
                .help(L10n.quickSwitcherHelp)
                .accessibilityLabel(L10n.quickSwitcherButton)
                .accessibilityIdentifier("Toolbar.QuickSwitcher")

                Button {
                    appState.toggleOutline()
                } label: {
                    Label(L10n.sidebarButton, systemImage: "sidebar.left")
                }
                .help(L10n.toggleSidebarHelp)
                .accessibilityLabel(L10n.toggleVaultSidebar)
                .accessibilityIdentifier("Toolbar.Sidebar")

                Button {
                    appState.toggleVaultSearch()
                } label: {
                    Label(L10n.searchVaultButton, systemImage: "text.magnifyingglass")
                }
                .help(L10n.searchAllNotesHelp)
                .accessibilityLabel(L10n.searchAllNotes)
                .accessibilityIdentifier("Toolbar.SearchVault")

                Button {
                    appState.toggleZenMode()
                } label: {
                    Label(L10n.zenButton, systemImage: "rectangle.expand.vertical")
                }
                .help(L10n.zenModeHelp)
                .accessibilityLabel(L10n.zenMode)
                .accessibilityIdentifier("Toolbar.Zen")

                Menu {
                    Button {
                        appState.requestInlineCompletion()
                    } label: {
                        Label(L10n.inlineCompletion, systemImage: "character.cursor.ibeam")
                    }
                    .help(L10n.inlineCompletionHelp)

                    Button {
                        appState.requestRewriteSelection()
                    } label: {
                        Label(L10n.rewriteSelection, systemImage: "pencil.and.outline")
                    }

                    Divider()

                    Button {
                        appState.summarizeDocument()
                    } label: {
                        Label(L10n.summarizeDocument, systemImage: "text.append")
                    }

                    Button {
                        appState.generateTitleAndTags()
                    } label: {
                        Label(L10n.generateTitleTags, systemImage: "tag")
                    }
                } label: {
                    Label(L10n.aiMenu, systemImage: "wand.and.stars")
                }
                .help(appState.ai.availabilityDescription)
                .accessibilityLabel(L10n.writingAssistant)
                .accessibilityIdentifier("Toolbar.AI")

                Button {
                    appState.showFindReplace.toggle()
                } label: {
                    Label(L10n.findButton, systemImage: "magnifyingglass")
                }
                .help(L10n.findHelp)
                .accessibilityLabel(L10n.findButton)
                .accessibilityIdentifier("Toolbar.Find")

                Button {
                    appState.showGoToLine.toggle()
                } label: {
                    Label(L10n.goToLine, systemImage: "arrow.up.arrow.down")
                }
                .help(L10n.goToLineHelp)
                .accessibilityLabel(L10n.goToLine)
                .accessibilityIdentifier("Toolbar.GoToLine")

                Button {
                    appState.viewMode = appState.viewMode.next
                } label: {
                    Label(L10n.previewButton, systemImage: appState.viewMode.toolbarIcon)
                }
                .help(appState.viewMode.toolbarHelp)
                .accessibilityLabel(L10n.previewButton)
                .accessibilityIdentifier("Toolbar.Preview")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.toggleCommandPalette()
                } label: {
                    Label(L10n.commandPaletteButton, systemImage: "command")
                }
                .help(L10n.commandPaletteHelp)
                .accessibilityLabel(L10n.commandPalette)
                .accessibilityIdentifier("Toolbar.CommandPalette")
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label(L10n.settingsButton, systemImage: "gearshape")
                }
                .help(L10n.settingsHelp)
                .accessibilityLabel(L10n.settingsButton)
                .accessibilityIdentifier("Toolbar.Settings")
            }
        }
        .animation(.snappy(duration: 0.22), value: appState.showFindReplace)
        .animation(.snappy(duration: 0.22), value: appState.showGoToLine)
        .animation(.snappy(duration: 0.22), value: appState.viewMode)
        .animation(.snappy(duration: 0.25), value: appState.showOutline)
        .animation(.snappy(duration: 0.2), value: appState.showCommandPalette)
        .animation(.snappy(duration: 0.2), value: appState.showQuickSwitcher)
        .animation(.snappy(duration: 0.2), value: appState.showVaultSearch)
        .animation(.snappy(duration: 0.2), value: appState.showVersionHistory)
        .animation(.snappy(duration: 0.3), value: appState.isZenMode)
        .animation(.snappy(duration: 0.2), value: appState.showWikiSuggestions)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            appState.open(urls: files)
            return true
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.isFileURL,
               ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) {
                appState.open(url: url)
                return .handled
            }

            guard url.scheme == "iriseditor", url.host == "wiki" else {
                return .systemAction
            }
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "target" })?
                .value
            guard let target else { return .discarded }
            appState.openWikiLink(target)
            return .handled
        })
    }

    @ViewBuilder
    private var overlayContent: some View {
        if appState.showCommandPalette
            || appState.showQuickSwitcher
            || appState.showVaultSearch
            || appState.showVersionHistory {
            ZStack(alignment: .top) {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture {
                        appState.dismissCommandPalette()
                        appState.dismissQuickSwitcher()
                        if appState.showVaultSearch { appState.toggleVaultSearch() }
                        if appState.showVersionHistory { appState.dismissVersionHistory() }
                    }
                    .transition(.opacity)

                if appState.showCommandPalette {
                    CommandPaletteView()
                        .padding(.top, 72)
                        .transition(
                            .scale(scale: 0.96, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -8))
                        )
                }

                if appState.showQuickSwitcher {
                    QuickSwitcherView()
                        .padding(.top, 72)
                        .transition(
                            .scale(scale: 0.96, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -8))
                        )
                }

                if appState.showVaultSearch {
                    VaultSearchView()
                        .padding(.top, 72)
                        .transition(
                            .scale(scale: 0.97, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -8))
                        )
                }

                if appState.showVersionHistory {
                    VersionHistoryView()
                        .padding(.top, 64)
                        .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                }
            }
            .zIndex(10)
        }
    }

    private var editorCard: some View {
        ZStack {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let second = appState.secondDocument {
                HSplitView {
                    primaryContent
                        .frame(minWidth: 280)
                    secondaryPane(second)
                        .frame(minWidth: 280)
                }
                .clipShape(.rect(cornerRadius: 13))
            } else {
                primaryContent
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(appState.settings.isHighContrast ? 1 : 0.7),
                    lineWidth: appState.settings.isHighContrast ? 1.5 : 0.5
                )
        }
        .padding(.horizontal, appState.isZenMode ? 64 : 12)
        .padding(.top, appState.isZenMode ? 28 : 10)
        .padding(.bottom, appState.isZenMode ? 28 : 8)
        .animation(.snappy(duration: 0.3), value: appState.isZenMode)
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch appState.viewMode {
        case .source:
            sourcePane(for: appState.document)
        case .preview:
            MarkdownPreviewView(
                markdown: appState.document.text,
                baseURL: previewBaseURL(for: appState.document),
                theme: appState.settings.previewTheme,
                onToggleTask: { text in appState.toggleTask(text: text) }
            )
            .clipShape(.rect(cornerRadius: 13))
        case .split:
            HSplitView {
                sourcePane(for: appState.document)
                    .frame(minWidth: 280)
                MarkdownPreviewView(
                    markdown: appState.document.text,
                    baseURL: previewBaseURL(for: appState.document),
                    theme: appState.settings.previewTheme,
                    onToggleTask: { text in appState.toggleTask(text: text) }
                )
                .frame(minWidth: 280)
            }
            .clipShape(.rect(cornerRadius: 13))
        }
    }

    private func secondaryPane(_ doc: EditorDocument) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(doc.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    appState.closeSecondPane()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help(L10n.closeSecondPane)
                .accessibilityLabel(L10n.closeSecondPane)
                .accessibilityIdentifier("SecondaryPane.Close")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider()
            sourcePane(for: doc)
        }
    }

    private func previewBaseURL(for document: EditorDocument) -> URL? {
        document.fileURL?.deletingLastPathComponent()
    }

    private func sourcePane(for document: EditorDocument) -> some View {
        TextEditorViewRepresentable(
            text: Binding(
                get: { document.text },
                set: { newValue in
                    guard document.text != newValue else { return }
                    document.text = newValue
                    document.isDirty = true
                }
            ),
            settings: appState.settings,
            documentID: document.id,
            fileURL: document.fileURL
        )
        .padding(1)
        .clipShape(.rect(cornerRadius: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var markdownToolbar: some View {
        HStack(spacing: 8) {
            formatButton("H1", prefix: "# ", help: L10n.headingOne)
            formatButton("B", prefix: "**", help: L10n.bold)
            formatButton("I", prefix: "*", help: L10n.italic)
            formatButton("`", prefix: "`", help: L10n.inlineCode)
            formatButton("S", prefix: "~~", help: L10n.strikethrough)

            Divider()
                .frame(height: 16)

            Button {
                appState.toggleMarkdownFormat(prefix: "- ")
            } label: {
                Image(systemName: "list.bullet")
            }
            .help(L10n.bulletedList)
            .accessibilityLabel(L10n.bulletedList)
            .accessibilityIdentifier("Toolbar.BulletedList")

            Button {
                appState.toggleMarkdownFormat(prefix: "> ")
            } label: {
                Image(systemName: "text.quote")
            }
            .help(L10n.blockQuote)
            .accessibilityLabel(L10n.blockQuote)
            .accessibilityIdentifier("Toolbar.BlockQuote")

            Button {
                appState.insertSnippet(Self.tableTemplate)
            } label: {
                Image(systemName: "tablecells")
            }
            .help(L10n.insertTable)
            .accessibilityLabel(L10n.insertTable)
            .accessibilityIdentifier("Toolbar.InsertTable")

            Spacer()
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Toolbar.Markdown")
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
        .accessibilityLabel(help)
        .accessibilityIdentifier("Toolbar.\(prefix)")
    }
}
