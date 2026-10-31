import AppKit
import SwiftUI

/// Unified Liquid Glass sidebar for the vault: files, outline, tags, backlinks, stars
/// and a graph mini-map, plus a persistent note filter shared by every pane.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            noteFilter
            panePicker
            Divider()
            content
            footer
        }
        .frame(width: 250)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        }
        .task {
            appState.refreshVaultIfNeeded()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                appState.chooseVaultFolder()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                    Text(vaultName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.chooseVaultFolder)
            .accessibilityLabel(L10n.chooseVaultFolder)
            .accessibilityIdentifier("Sidebar.ChooseVault")

            Spacer()

            Button {
                openWindow(id: AppWindows.graph)
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help(L10n.graphWindowHelp)
            .accessibilityLabel(L10n.openGraphWindow)
            .accessibilityIdentifier("Sidebar.OpenGraphWindow")

            Button {
                appState.refreshVaultIfNeeded()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help(L10n.refreshVault)
            .accessibilityLabel(L10n.refreshVault)
            .accessibilityIdentifier("Sidebar.Refresh")

            Button {
                appState.toggleOutline()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help(L10n.closeSidebar)
            .accessibilityLabel(L10n.closeSidebar)
            .accessibilityIdentifier("Sidebar.Close")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var vaultName: String {
        appState.effectiveVaultRoot?.lastPathComponent ?? L10n.noVault
    }

    // MARK: Filter

    private var noteFilter: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            SidebarSearchField(
                text: $appState.sidebarSearchQuery,
                placeholder: L10n.searchNotes
            )
            .frame(height: 16)

            if !appState.sidebarSearchQuery.isEmpty {
                Button {
                    appState.clearSidebarSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(L10n.clearNoteSearch)
                .accessibilityIdentifier("Sidebar.ClearSearch")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Sidebar.Search")
    }

    // MARK: Panes

    private var panePicker: some View {
        HStack(spacing: 1) {
            ForEach(VaultPane.allCases) { pane in
                Button {
                    appState.setSidebarPane(pane)
                } label: {
                    Image(systemName: pane.systemImage)
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.sidebarTab == pane
                                      ? Color.accentColor.opacity(0.16)
                                      : Color.clear)
                        }
                        .foregroundStyle(appState.sidebarTab == pane
                                         ? Color.accentColor
                                         : Color(nsColor: .secondaryLabelColor))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(pane.title)
                .accessibilityLabel(pane.title)
                .accessibilityValue(appState.sidebarTab == pane ? L10n.selected : L10n.notSelected)
                .accessibilityIdentifier("Sidebar.\(pane.rawValue)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
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
        HStack(spacing: 6) {
            Button {
                appState.createNote()
            } label: {
                Label(L10n.newNote, systemImage: "square.and.pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(L10n.newNote)
            .accessibilityIdentifier("Sidebar.NewNote")

            Button {
                appState.toggleStarForCurrentNote()
            } label: {
                Image(systemName: appState.isCurrentNoteStarred ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(appState.isCurrentNoteStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.document.fileURL == nil)
            .help(appState.isCurrentNoteStarred ? L10n.unstarNote : L10n.starNote)
            .accessibilityLabel(appState.isCurrentNoteStarred ? L10n.unstarNote : L10n.starNote)
            .accessibilityIdentifier("Sidebar.ToggleStar")

            Spacer()

            if appState.document.fileURL != nil {
                Button {
                    appState.archiveCurrentFile()
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(L10n.archiveNote)
                .accessibilityLabel(L10n.archiveNote)
                .accessibilityIdentifier("Sidebar.ArchiveNote")

                Button {
                    appState.renameCurrentFile()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(L10n.renameNote)
                .accessibilityLabel(L10n.renameNote)
                .accessibilityIdentifier("Sidebar.RenameNote")

                Button {
                    appState.deleteCurrentFile()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(L10n.deleteNote)
                .accessibilityLabel(L10n.deleteNote)
                .accessibilityIdentifier("Sidebar.DeleteNote")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - Search field

/// Plain-text field styled for the sidebar. `TextField` inside the glass chrome keeps
/// focus behaviour native while staying visually inline.
private struct SidebarSearchField: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .focused($isFocused)
            .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearch)) { _ in
                isFocused = true
            }
            .onSubmit {
                isFocused = false
            }
            .accessibilityLabel(placeholder)
            .accessibilityIdentifier("Sidebar.SearchField")
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
            ForEach(VaultFileListing.allCases) { option in
                Button {
                    appState.setVaultFileListing(option)
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 9.5, weight: .medium))
                        .frame(width: 20, height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(listing == option ? Color.accentColor.opacity(0.14) : .clear)
                        }
                        .foregroundStyle(listing == option ? Color.accentColor : Color.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityValue(listing == option ? L10n.selected : L10n.notSelected)
                .accessibilityIdentifier("Sidebar.Listing.\(option.rawValue)")
            }

            Spacer(minLength: 4)

            Button {
                appState.toggleVaultFileSortDirection()
            } label: {
                Image(systemName: appState.settings.vaultFileSortAscending
                      ? "arrow.up"
                      : "arrow.down")
                    .font(.system(size: 8.5, weight: .semibold))
            }
            .buttonStyle(.borderless)
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
        .padding(.bottom, 4)
    }
}

/// One note row used by the flat listings.
private struct NoteRow: View {
    let file: VaultFile
    var showsFolder: Bool = false
    var showsAge: Bool = false
    @EnvironmentObject private var appState: AppState

    private var isCurrent: Bool {
        appState.document.fileURL?.standardizedFileURL == file.url.standardizedFileURL
    }

    var body: some View {
        Button {
            appState.open(url: file.url)
            appState.refreshBacklinks()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
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
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isCurrent ? Color.accentColor.opacity(0.13) : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { appState.isFolderExpanded(folder.relativePath) },
            set: { appState.setFolder(folder.relativePath, expanded: $0) }
        )
    }

    var body: some View {
        if folder.subfolders.isEmpty, folder.relativePath.isEmpty {
            fileList
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: 1) {
                    fileList
                    ForEach(folder.subfolders) { subfolder in
                        VaultFolderRow(folder: subfolder)
                    }
                }
                .padding(.leading, 6)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
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
                .accessibilityLabel(displayName)
                .accessibilityValue(L10n.files(folder.fileCount))
                .accessibilityIdentifier("Sidebar.Folder.\(folder.relativePath)")
            }
            .disclosureGroupStyle(.automatic)
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
                Divider()
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
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isCurrent ? Color.accentColor.opacity(0.13) : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
                                .padding(.vertical, 4)
                                .contentShape(.rect)
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
                    .padding(.vertical, 2)
                    .contentShape(.rect)
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(tinted
                          ? Color.accentColor.opacity(0.07)
                          : Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
    @Environment(\.openWindow) private var openWindow
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
                    selectedNodeID: $selectedNodeID
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
                        openWindow(id: AppWindows.graph)
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .accessibilityIdentifier("Sidebar.Empty.\(title)")
    }
}

/// Small borderless icon button shared across the sidebar rows.
private struct IconButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .medium))
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
