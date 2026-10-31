import AppKit
import SwiftUI

/// Unified Liquid Glass sidebar for the vault: files, outline, tags, backlinks, stars
/// and a graph mini-map, plus a persistent note filter shared by every pane.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    /// Editor content width. Zero until the first layout pass; resizing is capped at
    /// half of it so the editor always keeps usable room, even in a narrow window.
    var viewportWidth: CGFloat = 0

    @FocusState private var isSearchFocused: Bool
    @FocusState private var isResizeHandleFocused: Bool
    @Namespace private var panePill
    @State private var dragStartWidth: CGFloat?
    @State private var isResizeHandleHovered = false
    @State private var isVaultButtonHovered = false
    @State private var isNewNoteHovered = false

    private let cornerRadius: CGFloat = 18
    private let resizeStep: CGFloat = 16

    private var minimumWidth: CGFloat {
        CGFloat(EditorSettings.sidebarWidthRange.lowerBound)
    }

    /// The widest the sidebar may get: never more than half the content area.
    private var maximumWidth: CGFloat {
        let range = EditorSettings.sidebarWidthRange
        guard viewportWidth > 0 else { return CGFloat(range.upperBound) }
        return CGFloat(min(range.upperBound, max(range.lowerBound, viewportWidth * 0.5)))
    }

    /// What is actually drawn, clamped to the current viewport.
    private var effectiveWidth: CGFloat {
        min(appState.sidebarWidth, maximumWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            noteFilter
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            panePicker
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            hairline

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(appState.sidebarTab)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity
                ))

            hairline

            footer
        }
        .frame(width: effectiveWidth)
        .background { SidebarGlassSurface(cornerRadius: cornerRadius) }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color(nsColor: .separatorColor).opacity(0.32),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) { resizeHandle }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        .animation(.snappy(duration: 0.22), value: appState.sidebarTab)
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearch)) { _ in
            isSearchFocused = true
        }
        .task {
            appState.refreshVaultIfNeeded()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 2) {
            Button {
                appState.chooseVaultFolder()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .symbolRenderingMode(.hierarchical)
                    Text(vaultName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(isVaultButtonHovered ? 0.10 : 0.05))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .onHover { isVaultButtonHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isVaultButtonHovered)
            .help(L10n.chooseVaultFolder)
            .accessibilityLabel(L10n.chooseVaultFolder)
            .accessibilityIdentifier("Sidebar.ChooseVault")

            Spacer()

            IconButton(
                systemImage: "macwindow.on.rectangle",
                label: L10n.graphWindowHelp,
                identifier: "Sidebar.OpenGraphWindow"
            ) {
                appState.openGraphTab()
            }
            .accessibilityLabel(L10n.openGraphWindow)

            IconButton(
                systemImage: "arrow.clockwise",
                label: L10n.refreshVault,
                identifier: "Sidebar.Refresh"
            ) {
                appState.refreshVaultIfNeeded()
            }

            IconButton(
                systemImage: "xmark",
                label: L10n.closeSidebar,
                identifier: "Sidebar.Close"
            ) {
                appState.toggleOutline()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var vaultName: String {
        appState.effectiveVaultRoot?.lastPathComponent ?? L10n.noVault
    }

    // MARK: Filter

    private var noteFilter: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSearchFocused ? Color.accentColor : Color.secondary)

            SidebarSearchField(
                text: $appState.sidebarSearchQuery,
                placeholder: L10n.searchNotes,
                focus: $isSearchFocused
            )
            .frame(height: 16)

            if !appState.sidebarSearchQuery.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        appState.clearSidebarSearch()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel(L10n.clearNoteSearch)
                .accessibilityIdentifier("Sidebar.ClearSearch")
            } else if isSearchFocused {
                Text("esc")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isSearchFocused ? 0.09 : 0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.12),
                    lineWidth: isSearchFocused ? 1 : 0.5
                )
        }
        .animation(.easeOut(duration: 0.16), value: isSearchFocused)
        .animation(.snappy(duration: 0.18), value: appState.sidebarSearchQuery.isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Sidebar.Search")
    }

    // MARK: Panes

    private var panePicker: some View {
        HStack(spacing: 2) {
            ForEach(VaultPane.allCases) { pane in
                SidebarPaneButton(
                    pane: pane,
                    isSelected: appState.sidebarTab == pane,
                    namespace: panePill
                ) {
                    appState.setSidebarPane(pane)
                }
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.sidebarTab {
        case .files:
            VaultFilesPane()
        case .outline:
            DocumentOutlineView()
        case .tags:
            VaultTagsPane()
        case .backlinks:
            VaultBacklinksPane()
        case .stars:
            VaultStarsPane()
        case .graph:
            VaultGraphPane()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                appState.createNote()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10))
                        .symbolRenderingMode(.hierarchical)
                    Text(L10n.newNote)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(isNewNoteHovered ? 0.10 : 0.05))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .onHover { isNewNoteHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isNewNoteHovered)
            .accessibilityLabel(L10n.newNote)
            .accessibilityIdentifier("Sidebar.NewNote")

            IconButton(
                systemImage: appState.isCurrentNoteStarred ? "star.fill" : "star",
                label: appState.isCurrentNoteStarred ? L10n.unstarNote : L10n.starNote,
                identifier: "Sidebar.ToggleStar",
                tint: appState.isCurrentNoteStarred ? .yellow : nil
            ) {
                appState.toggleStarForCurrentNote()
            }
            .disabled(appState.document.fileURL == nil)

            Spacer()

            if appState.document.fileURL != nil {
                IconButton(
                    systemImage: "archivebox",
                    label: L10n.archiveNote,
                    identifier: "Sidebar.ArchiveNote"
                ) {
                    appState.archiveCurrentFile()
                }

                IconButton(
                    systemImage: "pencil",
                    label: L10n.renameNote,
                    identifier: "Sidebar.RenameNote"
                ) {
                    appState.renameCurrentFile()
                }

                IconButton(
                    systemImage: "trash",
                    label: L10n.deleteNote,
                    identifier: "Sidebar.DeleteNote"
                ) {
                    appState.deleteCurrentFile()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Chrome helpers

    /// A hairline that fades into the glass at both ends instead of a hard rule.
    private var hairline: some View {
        SidebarHairline()
    }

    /// Invisible grab strip on the trailing edge. Dragging resizes the sidebar, a
    /// floating readout shows the live width, and a double-click restores the default.
    private var resizeHandle: some View {
        ZStack {
            // Always faintly visible so the grab area is discoverable, stronger while
            // hovered, focused or dragged.
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(
                    dragStartWidth != nil || isResizeHandleHovered || isResizeHandleFocused ? 0.3 : 0.12
                ))
                .frame(width: 3, height: 36)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
                .frame(width: 9, height: 44)
                .opacity(isResizeHandleFocused ? 1 : 0)

            if dragStartWidth != nil {
                Text("\(Int(appState.sidebarWidth))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                    .offset(y: -46)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(width: 9, height: 88)
        .contentShape(.rect)
        .focusable()
        .focused($isResizeHandleFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            withAnimation(.snappy(duration: 0.18)) {
                appState.sidebarWidth = max(minimumWidth, effectiveWidth - resizeStep)
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            withAnimation(.snappy(duration: 0.18)) {
                appState.sidebarWidth = min(maximumWidth, effectiveWidth + resizeStep)
            }
            return .handled
        }
        .onHover { hovering in
            isResizeHandleHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isResizeHandleHovered)
        .animation(.snappy(duration: 0.18), value: dragStartWidth == nil)
        .animation(.easeOut(duration: 0.12), value: isResizeHandleFocused)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = effectiveWidth
                    }
                    let start = dragStartWidth ?? effectiveWidth
                    appState.sidebarWidth = min(maximumWidth, start + value.translation.width)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy(duration: 0.22)) {
                appState.resetSidebarWidth()
            }
        }
        .help(L10n.resizeSidebar)
        .accessibilityLabel(L10n.resizeSidebar)
        .accessibilityIdentifier("Sidebar.ResizeHandle")
        .accessibilityValue("\(Int(effectiveWidth))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: appState.sidebarWidth = min(maximumWidth, effectiveWidth + resizeStep)
            case .decrement: appState.sidebarWidth = max(minimumWidth, effectiveWidth - resizeStep)
            @unknown default: break
            }
        }
    }
}

// MARK: - Glass

/// Layered Liquid Glass surface: the native glass material plus a faint top sheen and
/// accent aura so the panel reads as a curved, refractive volume rather than a flat card.
private struct SidebarGlassSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            GlassBackdrop(style: .regular, cornerRadius: cornerRadius, interactive: true)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 240
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    .clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Search field

/// Plain-text field styled for the sidebar. `TextField` inside the glass chrome keeps
/// focus behaviour native while staying visually inline.
private struct SidebarSearchField: View {
    @Binding var text: String
    let placeholder: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .focused(focus)
            .onExitCommand {
                if text.isEmpty {
                    focus.wrappedValue = false
                } else {
                    text = ""
                }
            }
            .onSubmit {
                focus.wrappedValue = false
            }
            .accessibilityLabel(placeholder)
            .accessibilityIdentifier("Sidebar.SearchField")
    }
}

// MARK: - Pane picker

/// One icon in the segmented pane picker. The selected state is a shared glassy pill
/// that slides between icons via `matchedGeometryEffect`.
private struct SidebarPaneButton: View {
    let pane: VaultPane
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 11, weight: .medium))
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(
                    isSelected
                        ? Color.accentColor
                        : (isHovered ? Color.primary.opacity(0.85) : Color(nsColor: .secondaryLabelColor))
                )
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.5)
                            }
                            .matchedGeometryEffect(id: "pane-pill", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(pane.title)
        .accessibilityLabel(pane.title)
        .accessibilityValue(isSelected ? L10n.selected : L10n.notSelected)
        .accessibilityIdentifier("Sidebar.\(pane.rawValue)")
    }
}

// MARK: - Shared row chrome

/// Hairline separator that fades into the glass at both ends.
private struct SidebarHairline: View {
    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                Color(nsColor: .separatorColor).opacity(0.55),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.6)
        .allowsHitTesting(false)
    }
}

/// Selection fill and hover wash shared by the note, star, and list rows.
private struct SidebarRowBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.07 : 0))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.22) : Color.white.opacity(isHovered ? 0.08 : 0),
                        lineWidth: 0.5
                    )
            }
    }
}

/// Lightweight hover wash for rows that have no persistent selected state.
private struct SidebarHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            }
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private extension View {
    func sidebarHoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(SidebarHoverHighlight(cornerRadius: cornerRadius))
    }
}

// MARK: - Files

private struct VaultFilesPane: View {
    @EnvironmentObject private var appState: AppState

    private var listing: VaultFileListing {
        appState.settings.vaultFileListing
    }

    private var files: [VaultFile] {
        switch listing {
        case .tree, .all:
            return appState.sidebarFilteredFiles
        case .recent:
            return appState.recentVaultFiles
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            listingBar

            if appState.vaultFiles.isEmpty {
                EmptyPane(
                    icon: "folder",
                    title: L10n.noNotesFound,
                    message: appState.effectiveVaultRoot == nil
                        ? L10n.noNotesMessage
                        : L10n.emptyVaultMessage
                )
            } else if files.isEmpty {
                EmptyPane(
                    icon: "magnifyingglass",
                    title: L10n.noSearchResults,
                    message: L10n.noSearchResultsHint
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        switch listing {
                        case .tree:
                            VaultFolderRow(folder: VaultScanner.folderTree(files: files))
                        case .all:
                            ForEach(files) { file in
                                NoteRow(file: file, showsFolder: true)
                            }
                        case .recent:
                            ForEach(files.prefix(30)) { file in
                                NoteRow(file: file, showsFolder: true, showsAge: true)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var listingBar: some View {
        HStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(VaultFileListing.allCases) { option in
                    Button {
                        appState.setVaultFileListing(option)
                    } label: {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 9.5, weight: .medium))
                            .symbolVariant(listing == option ? .fill : .none)
                            .frame(width: 22, height: 20)
                            .background {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(listing == option ? Color.accentColor.opacity(0.16) : .clear)
                            }
                            .foregroundStyle(listing == option ? Color.accentColor : Color.secondary)
                            .sidebarHoverHighlight(cornerRadius: 5)
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(listing == option ? L10n.selected : L10n.notSelected)
                    .accessibilityIdentifier("Sidebar.Listing.\(option.rawValue)")
                }
            }
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }

            Spacer(minLength: 4)

            Button {
                appState.toggleVaultFileSortDirection()
            } label: {
                Image(systemName: appState.settings.vaultFileSortAscending
                      ? "arrow.up"
                      : "arrow.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .sidebarHoverHighlight(cornerRadius: 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help(appState.settings.vaultFileSortAscending ? L10n.sortAscending : L10n.sortDescending)
            .accessibilityLabel(L10n.sortBy)
            .accessibilityIdentifier("Sidebar.SortDirection")

            Menu {
                Picker(L10n.sortBy, selection: Binding(
                    get: { appState.settings.vaultFileSort },
                    set: { appState.setVaultFileSort($0) }
                )) {
                    ForEach(VaultFileSort.allCases) { sort in
                        Label(sort.title, systemImage: sort.systemImage).tag(sort)
                    }
                }
                Divider()
                Button(L10n.collapseAll) { appState.collapseAllFolders() }
                    .disabled(listing != .tree)
                Button(L10n.expandAll) { appState.expandAllFolders() }
                    .disabled(listing != .tree)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 9.5, weight: .medium))
                    .frame(width: 22, height: 22)
                    .sidebarHoverHighlight(cornerRadius: 6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help(L10n.sortBy)
            .accessibilityLabel(L10n.columnMenu)
            .accessibilityIdentifier("Sidebar.FilesMenu")

            IconButton(systemImage: "plus", label: L10n.newNote, identifier: "Sidebar.FilesNewNote") {
                appState.createNote()
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

/// One note row used by the flat listings.
private struct NoteRow: View {
    let file: VaultFile
    var showsFolder: Bool = false
    var showsAge: Bool = false
    @EnvironmentObject private var appState: AppState

    @State private var isHovered = false

    private var isCurrent: Bool {
        appState.document.fileURL?.standardizedFileURL == file.url.standardizedFileURL
    }

    var body: some View {
        Button {
            appState.open(url: file.url)
            appState.refreshBacklinks()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isCurrent ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 9))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(file.title)
                        .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if showsFolder {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background {
                SidebarRowBackground(isSelected: isCurrent, isHovered: isHovered)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.snappy(duration: 0.18), value: isCurrent)
        .contextMenu {
            noteMenu(for: file, appState: appState)
        }
        .help(file.relativePath)
        .accessibilityLabel(file.title)
        .accessibilityValue(file.relativePath)
        .accessibilityIdentifier("Sidebar.File.\(file.relativePath)")
    }

    private var subtitle: String {
        if showsAge {
            let age = file.modified.formatted(.relative(presentation: .named))
            let folder = (file.relativePath as NSString).deletingLastPathComponent
            return folder.isEmpty ? age : "\(folder) · \(age)"
        }
        return (file.relativePath as NSString).deletingLastPathComponent
    }
}

/// Shared context menu for a note, used by every listing.
@MainActor
@ViewBuilder
private func noteMenu(for file: VaultFile, appState: AppState) -> some View {
    Button(L10n.openInSecondPane) {
        appState.openInSecondPane(url: file.url)
    }
    Button(appState.isStarred(file.url) ? L10n.unstarNote : L10n.starNote) {
        appState.toggleStar(for: file.url, title: file.title)
    }
    Divider()
    Button(L10n.copyWikiLink) {
        appState.copyWikiLink(to: file.url)
    }
    Button(L10n.showInFinder) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    Button(L10n.moveToTrash) {
        appState.moveToTrash(url: file.url)
    }
}

private struct VaultFolderRow: View {
    let folder: VaultFolder
    @EnvironmentObject private var appState: AppState

    @State private var isHovered = false

    private var isExpanded: Bool {
        appState.isFolderExpanded(folder.relativePath)
    }

    var body: some View {
        if folder.subfolders.isEmpty, folder.relativePath.isEmpty {
            fileList
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        appState.setFolder(folder.relativePath, expanded: !isExpanded)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 10))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                        Text(displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(folder.fileCount)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.snappy(duration: 0.2), value: isExpanded)
                .accessibilityLabel(displayName)
                .accessibilityValue(L10n.files(folder.fileCount))
                .accessibilityIdentifier("Sidebar.Folder.\(folder.relativePath)")

                if isExpanded {
                    VStack(alignment: .leading, spacing: 1) {
                        fileList
                        ForEach(folder.subfolders) { subfolder in
                            VaultFolderRow(folder: subfolder)
                        }
                    }
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var displayName: String {
        folder.relativePath.isEmpty
            ? (appState.effectiveVaultRoot?.lastPathComponent ?? L10n.vault)
            : folder.name
    }

    @ViewBuilder
    private var fileList: some View {
        ForEach(folder.files) { file in
            NoteRow(file: file, showsFolder: false)
        }
    }
}

// MARK: - Stars

private struct VaultStarsPane: View {
    @EnvironmentObject private var appState: AppState

    private var matches: [VaultBookmark] {
        let query = appState.sidebarSearchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return appState.currentVaultStars }
        return appState.currentVaultStars.filter {
            "\($0.title) \($0.folder)".lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.currentVaultStars.isEmpty {
                EmptyPane(
                    icon: "star",
                    title: L10n.noStarredNotes,
                    message: L10n.starNotesHint
                )
            } else if matches.isEmpty {
                EmptyPane(
                    icon: "magnifyingglass",
                    title: L10n.noSearchResults,
                    message: L10n.noSearchResultsHint
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(matches) { bookmark in
                            StarRow(bookmark: bookmark)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }

            if !appState.currentVaultStars.isEmpty {
                SidebarHairline()
                HStack {
                    Text(L10n.starredCount(appState.currentVaultStars.count))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.quaternary)
                    Spacer()
                    Button(L10n.clearStarred) {
                        appState.clearStars()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("Sidebar.ClearStars")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct StarRow: View {
    let bookmark: VaultBookmark
    @EnvironmentObject private var appState: AppState

    @State private var isHovered = false

    private var exists: Bool {
        FileManager.default.fileExists(atPath: bookmark.url.path)
    }

    private var isCurrent: Bool {
        appState.document.fileURL?.standardizedFileURL == bookmark.url.standardizedFileURL
    }

    var body: some View {
        Button {
            guard exists else { return }
            appState.open(url: bookmark.url)
            appState.refreshBacklinks()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.yellow.opacity(0.85))
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(bookmark.title)
                        .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(exists ? (isCurrent ? .primary : .secondary) : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !bookmark.folder.isEmpty {
                        Text(bookmark.folder)
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !exists {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .help(L10n.missingNote)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background {
                SidebarRowBackground(isSelected: isCurrent, isHovered: isHovered)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.snappy(duration: 0.18), value: isCurrent)
        .opacity(exists ? 1 : 0.55)
        .contextMenu {
            Button(L10n.removeStar) {
                appState.removeStar(for: bookmark.url)
            }
            if exists {
                Button(L10n.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([bookmark.url])
                }
            }
        }
        .help(bookmark.url.path)
        .accessibilityLabel(bookmark.title)
        .accessibilityValue(L10n.openNotePath(bookmark.url.lastPathComponent))
        .accessibilityIdentifier("Sidebar.Star.\(bookmark.id)")
    }
}

// MARK: - Tags

private struct VaultTagsPane: View {
    @EnvironmentObject private var appState: AppState

    private var tags: [VaultTag] {
        let query = appState.sidebarSearchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return appState.vaultTags }
        return appState.vaultTags.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.vaultTags.isEmpty {
                EmptyPane(
                    icon: "number",
                    title: L10n.noTagsYet,
                    message: L10n.addTagsHint
                )
            } else if tags.isEmpty {
                EmptyPane(
                    icon: "magnifyingglass",
                    title: L10n.noSearchResults,
                    message: L10n.noSearchResultsHint
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(tags) { tag in
                            Button {
                                appState.setSidebarPane(.files)
                                appState.sidebarSearchQuery = ""
                                appState.vaultSearchQuery = "#\(tag.name)"
                                appState.showVaultSearch = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text("#\(tag.name)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(tag.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .sidebarHoverHighlight(cornerRadius: 6)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                tagMenu(for: tag, appState: appState)
                            }
                            .accessibilityLabel("#\(tag.name)")
                            .accessibilityValue(L10n.notes(tag.count))
                            .accessibilityIdentifier("Sidebar.Tag.\(tag.name)")
                        }
                    }
                    .padding(6)
                }
            }
        }
        .accessibilityIdentifier("Sidebar.tags")
    }

    /// Filter the vault search by `tag`, or copy its `#tag` text.
    @MainActor
    @ViewBuilder
    private func tagMenu(for tag: VaultTag, appState: AppState) -> some View {
        Button(L10n.filterByTag(tag.name)) {
            appState.sidebarSearchQuery = ""
            appState.vaultSearchQuery = "#\(tag.name)"
            appState.showVaultSearch = true
        }
        Button(L10n.copyTag) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("#\(tag.name)", forType: .string)
        }
    }
}

// MARK: - Backlinks

private struct VaultBacklinksPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.document.fileURL == nil {
                EmptyPane(
                    icon: "arrow.triangle.branch",
                    title: L10n.saveToSeeBacklinks,
                    message: L10n.saveToSeeBacklinksHint
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !appState.vaultBacklinks.isEmpty {
                            sectionHeading(L10n.backlinksSection, count: appState.vaultBacklinks.count)
                            ForEach(appState.vaultBacklinks) { link in
                                BacklinkRow(link: link, tinted: false, identifierPrefix: "Sidebar.Backlink")
                            }
                        }

                        if !appState.vaultUnlinkedMentions.isEmpty {
                            sectionHeading(L10n.unlinkedMentionsTitle, count: appState.vaultUnlinkedMentions.count)
                                .padding(.top, 4)
                            ForEach(appState.vaultUnlinkedMentions) { link in
                                BacklinkRow(link: link, tinted: true, identifierPrefix: "Sidebar.UnlinkedMention")
                            }
                        }

                        if appState.vaultBacklinks.isEmpty, appState.vaultUnlinkedMentions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.quaternary)
                                Text(L10n.noBacklinks)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                Text(L10n.backlinksHint(appState.document.displayName))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.quaternary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 40)
                        }

                        siblingsSection
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var siblingsSection: some View {
        let siblings = appState.siblingNotes
        if !siblings.isEmpty {
            sectionHeading(L10n.siblingNotes, count: siblings.count)
                .padding(.top, 4)
            ForEach(siblings.prefix(12)) { file in
                Button {
                    appState.open(url: file.url)
                    appState.refreshBacklinks()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(file.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .sidebarHoverHighlight(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Sidebar.Sibling.\(file.relativePath)")
            }
        }
    }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            Text("\(count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }
}

private struct BacklinkRow: View {
    let link: VaultBacklink
    let tinted: Bool
    let identifierPrefix: String
    @EnvironmentObject private var appState: AppState

    @State private var isHovered = false

    var body: some View {
        Button {
            appState.open(url: link.sourceURL)
            appState.reveal(line: link.line)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(link.sourceTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(link.line)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
                if !link.excerpt.isEmpty {
                    Text(link.excerpt)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        tinted
                            ? Color.accentColor.opacity(isHovered ? 0.12 : 0.07)
                            : Color(nsColor: .quaternaryLabelColor).opacity(isHovered ? 0.45 : 0.28)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.5)
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .padding(.horizontal, 6)
        .contextMenu {
            Button(L10n.openInSecondPane) {
                appState.openInSecondPane(url: link.sourceURL)
            }
        }
        .accessibilityLabel(link.sourceTitle)
        .accessibilityValue(link.excerpt)
        .accessibilityIdentifier("\(identifierPrefix).\(link.sourceURL.lastPathComponent)")
    }
}

// MARK: - Graph

private struct VaultGraphPane: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedNodeID: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.graphScope, selection: Binding(
                get: { appState.showsGlobalGraph },
                set: { appState.setShowsGlobalGraph($0) }
            )) {
                Text(L10n.localGraph).tag(false)
                Text(L10n.vaultGraph).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .accessibilityIdentifier("Sidebar.GraphScope")

            if appState.vaultGraph.nodes.isEmpty {
                EmptyPane(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: L10n.noLocalGraph,
                    message: L10n.noLocalGraphHint
                )
            } else {
                GraphCanvasView(
                    graph: appState.vaultGraph,
                    showsLabels: appState.vaultGraph.nodes.count <= 22,
                    interactive: true,
                    selectedNodeID: $selectedNodeID,
                    onOpenNode: { nodeID in
                        appState.open(url: URL(fileURLWithPath: nodeID))
                        selectedNodeID = nil
                    }
                )
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let selected = appState.vaultGraph.nodes.first(where: { $0.id == selectedNodeID }) {
                    selectedNodeCard(selected)
                }

                HStack(spacing: 6) {
                    Text(L10n.graphStats(
                        nodes: appState.vaultGraph.nodes.count,
                        links: appState.vaultGraph.edges.count
                    ))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.quaternary)
                    Spacer(minLength: 0)
                    Button {
                        appState.openGraphTab()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help(L10n.graphWindowHelp)
                    .accessibilityLabel(L10n.openGraphWindow)
                    .accessibilityIdentifier("Sidebar.GraphExpand")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
    }

    private func selectedNodeCard(_ node: VaultGraphNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(node.title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
            Text(L10n.linkedNotes(node.linkCount))
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            Spacer(minLength: 0)
            Button(L10n.graphOpenNote) {
                appState.open(url: URL(fileURLWithPath: node.id))
                selectedNodeID = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5))
            .foregroundStyle(.tint)
            .accessibilityIdentifier("Sidebar.GraphOpen")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Shared empty state

private struct EmptyPane: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.045))
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 44, height: 44)
            .padding(.bottom, 1)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .accessibilityIdentifier("Sidebar.Empty.\(title)")
    }
}

/// Small borderless icon button shared across the sidebar chrome and rows.
private struct IconButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint ?? (isHovered ? Color.primary : Color.secondary))
                .frame(width: 22, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.09 : 0))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
