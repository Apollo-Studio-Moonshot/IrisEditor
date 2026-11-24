import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    /// Width of the content area, used to cap the sidebar at half the viewport.
    @State private var viewportWidth: CGFloat = 0

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
                        SidebarView(viewportWidth: viewportWidth)
                            .padding(.leading, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    editorCard
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(appState.settings.accentColor)
        .preferredColorScheme(appState.settings.appearance.colorScheme)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ViewportWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(ViewportWidthPreferenceKey.self) { width in
            viewportWidth = width
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
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.toggleOutline()
                } label: {
                    Label(L10n.sidebarButton, systemImage: "sidebar.left")
                }
                .help(L10n.toggleSidebarHelp)
                .accessibilityLabel(L10n.toggleVaultSidebar)
                .accessibilityIdentifier("Toolbar.Sidebar")
            }

            ToolbarItem(placement: .primaryAction) {
                viewModePicker
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

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

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
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
                    Label(L10n.goToLine, systemImage: "arrow.down.to.line")
                }
                .help(L10n.goToLineHelp)
                .accessibilityLabel(L10n.goToLine)
                .accessibilityIdentifier("Toolbar.GoToLine")

                Button {
                    appState.toggleVaultSearch()
                } label: {
                    Label(L10n.searchVaultButton, systemImage: "text.magnifyingglass")
                }
                .help(L10n.searchAllNotesHelp)
                .accessibilityLabel(L10n.searchAllNotes)
                .accessibilityIdentifier("Toolbar.SearchVault")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

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
                    appState.toggleCommandPalette()
                } label: {
                    Label(L10n.commandPaletteButton, systemImage: "command")
                }
                .help(L10n.commandPaletteHelp)
                .accessibilityLabel(L10n.commandPalette)
                .accessibilityIdentifier("Toolbar.CommandPalette")

                Button {
                    appState.toggleZenMode()
                } label: {
                    Label(L10n.zenButton, systemImage: appState.isZenMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
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

    private var showsEditorChrome: Bool {
        !appState.isZenMode
    }

    private var editorCard: some View {
        ZStack {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                if showsEditorChrome && (appState.showFindReplace || appState.showGoToLine) {
                    FindReplacePanel()
                        .transition(.move(edge: .top).combined(with: .opacity))
                    chromeHairline
                }

                if showsEditorChrome && appState.viewMode != .preview {
                    markdownToolbar
                        .transition(.opacity)
                    chromeHairline
                }

                if let second = appState.secondDocument {
                    HSplitView {
                        primaryContent
                            .frame(minWidth: 280)
                        secondaryPane(second)
                            .frame(minWidth: 280)
                    }
                } else {
                    primaryContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            preview(for: appState.document)
                .clipShape(.rect(cornerRadius: 13))
        case .split:
            HSplitView {
                sourcePane(for: appState.document)
                    .frame(minWidth: 280)
                preview(for: appState.document)
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

    /// Lets the preview expand `![[…]]` embeds without owning file access.
    private var transclusionResolver: @MainActor (String, URL?) -> TransclusionContent {
        { target, directory in
            appState.transclusion(target, relativeTo: directory)
        }
    }

    private func preview(for document: EditorDocument) -> some View {
        MarkdownPreviewView(
            markdown: document.text,
            baseURL: previewBaseURL(for: document),
            theme: appState.settings.previewTheme,
            onToggleTask: { text in appState.toggleTask(text: text) }
        )
        .environment(\.transclusionResolver, transclusionResolver)
        .environment(\.openVaultTasks, appState.vaultOpenTasks)
        .environment(\.vaultTaskHostPath, document.fileURL?.standardizedFileURL.path)
        .environment(\.completeVaultTask) { task in
            appState.completeVaultTask(task)
        }
        .environment(\.openVaultTask) { task in
            appState.open(url: task.sourceURL)
            appState.reveal(line: task.line)
        }
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
            fileURL: document.fileURL,
            headingMarks: appState.headingMarks(in: document),
            onOpenHeadingSource: { link in
                appState.open(url: link.sourceURL)
                appState.reveal(line: link.line)
            }
        )
        .padding(1)
        .clipShape(.rect(cornerRadius: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewModePicker: some View {
        Picker(L10n.previewButton, selection: $appState.viewMode) {
            ForEach(EditorViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.toolbarIcon)
                    .tag(mode)
                    .accessibilityLabel(mode.title)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 148)
        .help(L10n.previewModeHelp)
        .accessibilityLabel(L10n.previewButton)
        .accessibilityIdentifier("Toolbar.Preview")
    }

    private var chromeHairline: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.45))
            .frame(height: 0.5)
            .allowsHitTesting(false)
    }

    private var markdownToolbar: some View {
        HStack(spacing: 2) {
            Menu {
                headingButton(L10n.headingLevel(1), prefix: "# ")
                headingButton(L10n.headingLevel(2), prefix: "## ")
                headingButton(L10n.headingLevel(3), prefix: "### ")
            } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 26, height: 22)
            }
            .menuIndicator(.hidden)
            .help(L10n.heading)
            .accessibilityLabel(L10n.heading)
            .accessibilityIdentifier("Toolbar.Heading")

            toolbarDivider

            formatButton(systemImage: "bold", prefix: "**", help: L10n.bold)
            formatButton(systemImage: "italic", prefix: "*", help: L10n.italic)
            formatButton(systemImage: "strikethrough", prefix: "~~", help: L10n.strikethrough)
            formatButton(
                systemImage: "chevron.left.forwardslash.chevron.right",
                prefix: "`",
                help: L10n.inlineCode
            )

            toolbarDivider

            formatButton(
                systemImage: "list.bullet",
                prefix: "- ",
                help: L10n.bulletedList,
                identifier: "Toolbar.BulletedList"
            )
            formatButton(
                systemImage: "list.number",
                prefix: "1. ",
                help: L10n.numberedList,
                identifier: "Toolbar.NumberedList"
            )
            formatButton(
                systemImage: "text.quote",
                prefix: "> ",
                help: L10n.blockQuote,
                identifier: "Toolbar.BlockQuote"
            )

            Button {
                appState.insertSnippet(Self.tableTemplate)
            } label: {
                Image(systemName: "tablecells")
                    .frame(width: 26, height: 22)
            }
            .help(L10n.insertTable)
            .accessibilityLabel(L10n.insertTable)
            .accessibilityIdentifier("Toolbar.InsertTable")

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .medium))
        .labelStyle(.iconOnly)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Toolbar.Markdown")
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.7))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 4)
    }

    private func headingButton(_ title: String, prefix: String) -> some View {
        Button(title) {
            appState.toggleMarkdownFormat(prefix: prefix)
        }
        .accessibilityIdentifier("Toolbar.\(prefix)")
    }

    private func formatButton(
        systemImage: String,
        prefix: String,
        help: String,
        identifier: String? = nil
    ) -> some View {
        Button {
            appState.toggleMarkdownFormat(prefix: prefix)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 26, height: 22)
                .contentShape(.rect)
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(identifier ?? "Toolbar.\(prefix)")
    }
}

/// Reports the editor content width so the sidebar can cap itself at half the viewport.
private struct ViewportWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
