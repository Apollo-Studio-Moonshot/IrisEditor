import AppKit
import SwiftUI

/// Unified Liquid Glass sidebar for the vault: files, outline, tags, backlinks, and graph.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            panePicker
            Divider()
            content
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

    private var panePicker: some View {
        HStack(spacing: 2) {
            ForEach(VaultPane.allCases) { pane in
                Button {
                    appState.setSidebarPane(pane)
                } label: {
                    Image(systemName: pane.systemImage)
                        .font(.system(size: 11, weight: .medium))
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
                }
                .buttonStyle(.plain)
                .help(pane.title)
                .accessibilityLabel(pane.title)
                .accessibilityValue(appState.sidebarTab == pane ? L10n.selected : L10n.notSelected)
                .accessibilityIdentifier("Sidebar.\(pane.rawValue)")
            }
        }
        .padding(.horizontal, 8)
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
        case .graph:
            VaultGraphPane()
        }
    }
}

// MARK: - Files

private struct VaultFilesPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.vaultFiles.isEmpty {
                EmptyPane(
                    icon: "folder",
                    title: L10n.noNotesFound,
                    message: appState.effectiveVaultRoot == nil
                        ? L10n.noNotesMessage
                        : L10n.emptyVaultMessage
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        VaultFolderRow(folder: VaultScanner.folderTree(files: appState.vaultFiles))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
            }

            Divider()
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

                Spacer()

                if appState.document.fileURL != nil {
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
            .padding(.vertical, 7)
        }
    }
}

private struct VaultFolderRow: View {
    let folder: VaultFolder
    @EnvironmentObject private var appState: AppState
    @State private var isExpanded: Bool

    init(folder: VaultFolder) {
        self.folder = folder
        _isExpanded = State(initialValue: folder.relativePath.isEmpty)
    }

    var body: some View {
        if folder.subfolders.isEmpty, folder.relativePath.isEmpty {
            fileList
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
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
                    Text(folder.relativePath.isEmpty
                         ? (appState.effectiveVaultRoot?.lastPathComponent ?? L10n.vault)
                         : folder.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityLabel(folder.relativePath.isEmpty
                                    ? (appState.effectiveVaultRoot?.lastPathComponent ?? L10n.vault)
                                    : folder.name)
                .accessibilityValue(L10n.files(folder.files.count))
                .accessibilityIdentifier("Sidebar.Folder.\(folder.relativePath)")
            }
            .disclosureGroupStyle(.automatic)
        }
    }

    @ViewBuilder
    private var fileList: some View {
        ForEach(folder.files) { file in
            Button {
                appState.open(url: file.url)
                appState.refreshBacklinks()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                        .foregroundStyle(isCurrent(file) ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    Text(file.title)
                        .font(.system(size: 11.5, weight: isCurrent(file) ? .semibold : .regular))
                        .foregroundStyle(isCurrent(file) ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isCurrent(file) ? Color.accentColor.opacity(0.13) : .clear)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(L10n.openInSecondPane) {
                    appState.openInSecondPane(url: file.url)
                }
                Button(L10n.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
            }
            .help(file.relativePath)
            .accessibilityLabel(file.title)
            .accessibilityValue(file.relativePath)
            .accessibilityIdentifier("Sidebar.File.\(file.relativePath)")
        }
    }

    private func isCurrent(_ file: VaultFile) -> Bool {
        appState.document.fileURL?.standardizedFileURL == file.url.standardizedFileURL
    }
}

// MARK: - Tags

private struct VaultTagsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.vaultTags.isEmpty {
                EmptyPane(
                    icon: "number",
                    title: L10n.noTagsYet,
                    message: L10n.addTagsHint
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.vaultTags) { tag in
                            Button {
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
            } else if appState.vaultBacklinks.isEmpty {
                EmptyPane(
                    icon: "arrow.triangle.branch",
                    title: L10n.noBacklinks,
                    message: L10n.backlinksHint(appState.document.displayName)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        Text(L10n.linkedNotes(appState.vaultBacklinks.count))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)

                        ForEach(appState.vaultBacklinks) { link in
                            Button {
                                appState.open(url: link.sourceURL)
                                appState.reveal(line: link.line)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.sourceTitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(link.excerpt)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .accessibilityLabel(link.sourceTitle)
                            .accessibilityValue(link.excerpt)
                            .accessibilityIdentifier("Sidebar.Backlink.\(link.sourceURL.lastPathComponent)")
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - Graph

private struct VaultGraphPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.vaultGraph.nodes.isEmpty {
                EmptyPane(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: L10n.noLocalGraph,
                    message: L10n.noLocalGraphHint
                )
            } else {
                LocalGraphView(graph: appState.vaultGraph) { path in
                    appState.open(url: URL(fileURLWithPath: path))
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: 320)

                Text("\(appState.vaultGraph.nodes.count) notes · \(appState.vaultGraph.edges.count) links")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct LocalGraphView: View {
    let graph: VaultGraph
    var onSelect: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let positions = layout(in: geometry.size)
            Canvas { context, _ in
                for edge in graph.edges {
                    guard let from = positions[edge.source],
                          let to = positions[edge.target] else { continue }
                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                }

                for node in graph.nodes {
                    guard let point = positions[node.id] else { continue }
                    let radius: CGFloat = node.isCurrent ? 17 : 11
                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let color: Color = node.isCurrent ? .accentColor : Color(nsColor: .secondaryLabelColor)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(node.isCurrent ? 0.85 : 0.45)))
                    context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1)

                    let label = Text(node.title)
                        .font(.system(size: node.isCurrent ? 10 : 9, weight: node.isCurrent ? .semibold : .regular))
                        .foregroundStyle(.secondary)
                    context.draw(label, at: CGPoint(x: point.x, y: point.y + radius + 8))
                }
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("Local note graph")
    }

    private func layout(in size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let others = graph.nodes.filter { !$0.isCurrent }
        let radius = max(36, min(size.width, size.height) / 2 - 34)
        var result: [String: CGPoint] = [:]

        if let current = graph.nodes.first(where: { $0.isCurrent }) {
            result[current.id] = center
        }

        for (index, node) in others.enumerated() {
            let angle = (Double(index) / Double(max(1, others.count))) * 2 * .pi - .pi / 2
            result[node.id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
        return result
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
    }
}
