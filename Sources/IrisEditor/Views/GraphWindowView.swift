import SwiftUI

/// Standalone, resizable graph window (⇧⌘G).
///
/// The window keeps its own scope, filter and node limit so exploring the vault graph
/// never disturbs the sidebar mini-map. Selecting a node fills the inspector on the
/// right; double-clicking (or the inspector's Open button) opens the note in the main
/// window.
struct GraphWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    @AppStorage("IrisEditor.GraphScope") private var scopeRaw = GraphScope.vault.rawValue
    @AppStorage("IrisEditor.GraphShowLabels") private var showsLabels = true
    @AppStorage("IrisEditor.GraphShowOrphans") private var showsOrphans = true
    @AppStorage("IrisEditor.GraphDepth") private var depth = 2
    @AppStorage("IrisEditor.GraphLimit") private var nodeLimit = 250
    @AppStorage("IrisEditor.GraphInspector") private var showsInspector = true

    @StateObject private var model = GraphWindowModel()

    private var filterText: String { model.filterText }
    private var selectedNodeID: String? { model.selectedNodeID }
    private var selectedTag: String? { model.selectedTag }
    private var selectedFolder: String? { model.selectedFolder }

    private var scope: GraphScope {
        GraphScope(rawValue: scopeRaw) ?? .vault
    }

    private var baseGraph: VaultGraph {
        appState.buildGraph(scope: scope, depth: depth, limit: nodeLimit)
    }

    /// Base graph plus every user filter applied.
    private var graph: VaultGraph {
        var result = baseGraph
        if !showsOrphans {
            let orphans = Set(result.nodes.filter { $0.linkCount == 0 }.map(\.id))
            result = result.removing(nodesIDs: orphans)
        }
        let needles = filterText
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        if !needles.isEmpty {
            let hidden = Set(result.nodes.filter { node in
                let haystack = "\(node.title) \(node.folder) \(node.tags.joined(separator: " "))".lowercased()
                return !needles.allSatisfy { haystack.contains($0) }
            }.map(\.id))
            result = result.removing(nodesIDs: hidden)
        }
        if let selectedTag {
            let hidden = Set(result.nodes.filter { node in
                !node.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
            }.map(\.id))
            result = result.removing(nodesIDs: hidden)
        }
        if let selectedFolder {
            let hidden = Set(result.nodes.filter { $0.folder != selectedFolder }.map(\.id))
            result = result.removing(nodesIDs: hidden)
        }
        return result
    }

    private var hiddenByFilter: Int {
        max(0, baseGraph.nodes.count - graph.nodes.count)
    }

    private var selectedNode: VaultGraphNode? {
        guard let selectedNodeID else { return nil }
        return graph.nodes.first { $0.id == selectedNodeID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                canvas
                if showsInspector {
                    inspector
                        .frame(minWidth: 210, idealWidth: 250, maxWidth: 340)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(VisualEffectBackground())
        .onChange(of: appState.graphWindowRequested) { _, requested in
            if requested { appState.consumeGraphWindowRequest() }
        }
        .onChange(of: graph.nodes.map(\.id)) { _, ids in
            // Keep the selection only while its node is still drawn.
            model.pruneSelection(keeping: ids)
        }
        .onAppear { appState.refreshVaultIfNeeded() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $scopeRaw) {
                ForEach(GraphScope.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .accessibilityIdentifier("GraphWindow.Scope")

            if scope == .local {
                Stepper(value: $depth, in: 1...4) {
                    Text(L10n.graphDepth + " \(depth)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .fixedSize()
                .help(L10n.graphDepth)
            }

            searchField

            Menu {
                Toggle(L10n.showLabels, isOn: $showsLabels)
                Toggle(L10n.showOrphans, isOn: $showsOrphans)
                Divider()
                Picker(L10n.graphNodeLimit, selection: $nodeLimit) {
                    Text("75").tag(75)
                    Text("150").tag(150)
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                }
                Divider()
                tagMenu
                folderMenu
                if selectedTag != nil || selectedFolder != nil {
                    Divider()
                    Button(L10n.clearFilters) {
                        model.clearFilters()
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.columnMenu)
            .accessibilityLabel(L10n.columnMenu)
            .accessibilityIdentifier("GraphWindow.Options")

            Button {
                withAnimation(.snappy(duration: 0.2)) { showsInspector.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.borderless)
            .help(L10n.toggleInspector)
            .accessibilityIdentifier("GraphWindow.Inspector")

            Button {
                appState.refreshVaultIfNeeded()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.refreshVault)
            .accessibilityIdentifier("GraphWindow.Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            TextField(
                L10n.graphFilter,
                text: Binding(
                    get: { model.filterText },
                    set: { model.filterText = $0 }
                )
            )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .accessibilityIdentifier("GraphWindow.Filter")
            if !filterText.isEmpty {
                Button {
                    model.clearFilterText()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(L10n.clearNoteSearch)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7))
        .frame(maxWidth: 260)
    }

    private var tagMenu: some View {
        Menu(L10n.tagsSection.capitalized) {
            ForEach(baseGraph.tags, id: \.self) { tag in
                Button {
                    model.toggleTag(tag)
                } label: {
                    if selectedTag == tag {
                        Label(tag, systemImage: "checkmark")
                    } else {
                        Text(tag)
                    }
                }
            }
        }
        .disabled(baseGraph.tags.isEmpty)
    }

    private var folderMenu: some View {
        Menu(L10n.groupByFolder) {
            ForEach(baseGraph.folders, id: \.self) { folder in
                Button {
                    model.toggleFolder(folder)
                } label: {
                    if selectedFolder == folder {
                        Label(folder.isEmpty ? L10n.vault : folder, systemImage: "checkmark")
                    } else {
                        Text(folder.isEmpty ? L10n.vault : folder)
                    }
                }
            }
        }
        .disabled(baseGraph.folders.count < 2)
    }

    // MARK: Canvas

    @ViewBuilder
    private var canvas: some View {
        if graph.nodes.isEmpty {
            emptyState
        } else {
            ZStack(alignment: .bottomLeading) {
                GraphCanvasView(
                    graph: graph,
                    showsLabels: showsLabels,
                    interactive: true,
                    selectedNodeID: Binding(
                        get: { model.selectedNodeID },
                        set: { model.selectedNodeID = $0 }
                    )
                )
                statusBar
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(L10n.graphStats(nodes: graph.nodes.count, links: graph.edges.count))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            if hiddenByFilter > 0 {
                Text(L10n.graphFiltered(hidden: hiddenByFilter))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            if let selectedNode {
                Button {
                    appState.openFromGraph(url: URL(fileURLWithPath: selectedNode.id))
                    if !NSEvent.modifierFlags.contains(.option) {
                        dismissGraphWindow()
                    }
                } label: {
                    Label(selectedNode.title, systemImage: "arrow.up.forward.square")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help(L10n.openNotePath(selectedNode.title))
                .accessibilityIdentifier("GraphWindow.OpenSelection")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)
            Text(hiddenByFilter > 0 ? L10n.graphNoMatches : L10n.graphNoNotes)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(L10n.graphNoNotesHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
            if hiddenByFilter > 0 {
                Button(L10n.clearFilters) {
                    resetFilters()
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Inspector

    @ViewBuilder
    private var inspector: some View {
        if let node = selectedNode {
            GraphInspector(
                node: node,
                graph: graph,
                onOpen: { url in
                    appState.openFromGraph(url: url)
                    if !NSEvent.modifierFlags.contains(.option) {
                        dismissGraphWindow()
                    }
                },
                onSelect: { model.selectedNodeID = $0 }
            )
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.quaternary)
                Text(L10n.selectGraphNode)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        }
    }

    private func resetFilters() {
        model.resetFilters()
    }

    private func dismissGraphWindow() {
        dismissWindow(id: AppWindows.graph)
    }
}

// MARK: - Inspector

/// Details for one graph node: tags, out-links and back-links, each clickable.
private struct GraphInspector: View {
    let node: VaultGraphNode
    let graph: VaultGraph
    let onOpen: (URL) -> Void
    let onSelect: (String) -> Void

    private var outgoing: [VaultGraphNode] {
        let ids = Set(graph.edges.filter { $0.source == node.id }.map(\.target))
        return graph.nodes.filter { ids.contains($0.id) }
    }

    private var incoming: [VaultGraphNode] {
        let ids = Set(graph.edges.filter { $0.target == node.id }.map(\.source))
        return graph.nodes.filter { ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.title)
                        .font(.system(size: 13, weight: .semibold))
                        .textSelection(.enabled)
                    if !node.folder.isEmpty {
                        Label(node.folder, systemImage: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(L10n.linkedNotes(node.linkCount))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !node.tags.isEmpty {
                    section(L10n.tagsSection) {
                        FlowTags(tags: node.tags)
                    }
                }

                linkSection(L10n.linkedNotesSection, nodes: outgoing, empty: L10n.noBacklinks)
                linkSection(L10n.backlinksSection, nodes: incoming, empty: L10n.noBacklinks)

                Button {
                    onOpen(URL(fileURLWithPath: node.id))
                } label: {
                    Label(L10n.graphOpenNote, systemImage: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .accessibilityIdentifier("Graph.Inspector.Open")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            content()
        }
    }

    private func linkSection(_ title: String, nodes: [VaultGraphNode], empty: String) -> some View {
        section(title) {
            if nodes.isEmpty {
                Text(empty)
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(nodes) { linked in
                        Button {
                            onSelect(linked.id)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(linked.title)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Graph.Inspector.Link.\(linked.id)")
                    }
                }
            }
        }
    }
}

/// Simple wrapping tag chips without needing a layout protocol.
private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { tag in
                        Text("#" + tag)
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.6), in: .capsule)
                    }
                }
            }
        }
    }

    /// Greedy packing: tags are short, so a fixed characters-per-row budget is enough.
    private var rows: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var width = 0
        for tag in tags {
            let cost = tag.count + 2
            if width + cost > 28, !current.isEmpty {
                result.append(current)
                current = []
                width = 0
            }
            current.append(tag)
            width += cost
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - Model

/// Filter + selection state for ``GraphWindowView``.
///
/// A reference type so every mutation happens through `model` instead of writing
/// `@State` from non-mutating view methods.
@MainActor
final class GraphWindowModel: ObservableObject {
    @Published var filterText = ""
    @Published var selectedNodeID: String?
    @Published var selectedTag: String?
    @Published var selectedFolder: String?

    /// Drops the selection when its node is filtered or scrolled out of view.
    func pruneSelection(keeping ids: [String]) {
        guard let selectedNodeID, !ids.contains(selectedNodeID) else { return }
        self.selectedNodeID = nil
    }

    func toggleTag(_ tag: String) {
        selectedTag = selectedTag == tag ? nil : tag
    }

    func toggleFolder(_ folder: String) {
        selectedFolder = selectedFolder == folder ? nil : folder
    }

    func clearFilterText() {
        filterText = ""
    }

    func clearFilters() {
        selectedTag = nil
        selectedFolder = nil
    }

    func resetFilters() {
        filterText = ""
        selectedTag = nil
        selectedFolder = nil
    }
}

// MARK: - Window ids

/// Identifiers for auxiliary windows opened with `openWindow`.
enum AppWindows {
    static let graph = "graph"
}
