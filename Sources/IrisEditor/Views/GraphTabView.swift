import SwiftUI

/// Obsidian-style graph workspace tab.
///
/// The graph lives in the main window's tab strip instead of a separate window, the
/// way Obsidian does it: an immersive dark canvas fills the tab while a floating
/// Liquid Glass panel on the left carries the search field, scope picker and the
/// Display/Forces sliders. Selecting a node lights up its neighbourhood; double-clicking
/// (or the inspector's Open button) jumps to the note in a document tab while keeping
/// the graph tab open in the background.
struct GraphTabView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("IrisEditor.GraphScope") private var scopeRaw = GraphScope.vault.rawValue
    @AppStorage("IrisEditor.GraphShowLabels") private var showsLabels = true
    @AppStorage("IrisEditor.GraphShowOrphans") private var showsOrphans = true
    @AppStorage("IrisEditor.GraphDepth") private var depth = 2
    @AppStorage("IrisEditor.GraphLimit") private var nodeLimit = 250
    @AppStorage("IrisEditor.GraphInspector") private var showsInspector = false
    @AppStorage("IrisEditor.GraphPanelCollapsed") private var panelCollapsed = false
    @AppStorage("IrisEditor.GraphCenterForce") private var centerForce = 1.0
    @AppStorage("IrisEditor.GraphLinkDistance") private var linkDistance = 1.0
    @AppStorage("IrisEditor.GraphLinkForce") private var linkForce = 1.0
    @AppStorage("IrisEditor.GraphNodeSize") private var nodeSize = 1.0

    @StateObject private var model = GraphTabModel()

    private var filterText: String { model.filterText }
    private var selectedNodeID: String? { model.selectedNodeID }
    private var selectedTag: String? { model.selectedTag }
    private var selectedFolder: String? { model.selectedFolder }

    private var scope: GraphScope {
        GraphScope(rawValue: scopeRaw) ?? .vault
    }

    private var forces: GraphForces {
        var value = GraphForces()
        value.centerForce = CGFloat(centerForce)
        value.linkDistance = CGFloat(linkDistance)
        value.linkForce = CGFloat(linkForce)
        value.nodeScale = CGFloat(nodeSize)
        return value
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
        ZStack {
            canvas
        }
        .overlay(alignment: .topLeading) {
            settingsPanel
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            if showsInspector {
                inspector
                    .frame(width: 250)
                    .padding(12)
            }
        }
        .clipShape(.rect(cornerRadius: 13))
        .onChange(of: graph.nodes.map(\.id)) { _, ids in
            // Keep the selection only while its node is still drawn.
            model.pruneSelection(keeping: ids)
        }
        .onAppear { appState.refreshVaultIfNeeded() }
        .accessibilityIdentifier("GraphTab")
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
                    ),
                    onOpenNode: { nodeID in
                        appState.openFromGraph(url: URL(fileURLWithPath: nodeID))
                    },
                    forces: forces,
                    immersive: true
                )
                statusBar
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(L10n.graphStats(nodes: graph.nodes.count, links: graph.edges.count))
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.75))
            if hiddenByFilter > 0 {
                Text(L10n.graphFiltered(hidden: hiddenByFilter))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            if let selectedNode {
                Button {
                    appState.openFromGraph(url: URL(fileURLWithPath: selectedNode.id))
                } label: {
                    Label(selectedNode.title, systemImage: "arrow.up.forward.square")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(L10n.openNotePath(selectedNode.title))
                .accessibilityIdentifier("GraphTab.OpenSelection")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 9, interactive: true)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.white.opacity(0.25))
            Text(hiddenByFilter > 0 ? L10n.graphNoMatches : L10n.graphNoNotes)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(L10n.graphNoNotesHint)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.3))
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
        .background(Color(nsColor: .black))
    }

    // MARK: Settings panel

    @ViewBuilder
    private var settingsPanel: some View {
        if panelCollapsed {
            Button {
                withAnimation(.snappy(duration: 0.22)) { panelCollapsed = false }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.85))
            .background {
                GlassBackdrop(style: .regular, cornerRadius: 9, interactive: true)
            }
            .help(L10n.graphShowSettings)
            .accessibilityLabel(L10n.graphShowSettings)
            .accessibilityIdentifier("GraphTab.ExpandPanel")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                panelHeader
                Divider().opacity(0.4)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        searchField

                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $scopeRaw) {
                                ForEach(GraphScope.allCases) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityIdentifier("GraphTab.Scope")

                            if scope == .local {
                                Stepper(value: $depth, in: 1...4) {
                                    Text(L10n.graphDepth + " \(depth)")
                                        .font(.system(size: 10.5))
                                        .monospacedDigit()
                                }
                                .controlSize(.small)
                                .fixedSize()
                                .help(L10n.graphDepth)
                            }
                        }

                        displaySection
                        forcesSection
                        filtersSection
                    }
                    .padding(12)
                }
            }
            .frame(width: 228)
            .frame(maxHeight: 460)
            .background {
                GlassBackdrop(style: .regular, cornerRadius: 12, interactive: true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityIdentifier("GraphTab.Panel")
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Text(L10n.graphSettingsTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 0)

            Button {
                withAnimation(.snappy(duration: 0.2)) { showsInspector.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 10.5))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showsInspector ? Color.accentColor : Color.white.opacity(0.6))
            .help(L10n.toggleInspector)
            .accessibilityIdentifier("GraphTab.Inspector")

            Button {
                appState.refreshVaultIfNeeded()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.6))
            .help(L10n.refreshVault)
            .accessibilityIdentifier("GraphTab.Refresh")

            Button {
                withAnimation(.snappy(duration: 0.22)) { panelCollapsed = true }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.6))
            .help(L10n.graphHideSettings)
            .accessibilityIdentifier("GraphTab.CollapsePanel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
            TextField(
                L10n.graphFilter,
                text: Binding(
                    get: { model.filterText },
                    set: { model.filterText = $0 }
                )
            )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .accessibilityIdentifier("GraphTab.Filter")
            if !filterText.isEmpty {
                Button {
                    model.clearFilterText()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.4))
                .accessibilityLabel(L10n.clearNoteSearch)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.09), in: .rect(cornerRadius: 7))
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(L10n.graphDisplaySection)

            forceSlider(label: L10n.graphNodeSizeSetting, value: $nodeSize, range: 0.5...2.5)

            Toggle(L10n.showLabels, isOn: $showsLabels)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Toggle(L10n.showOrphans, isOn: $showsOrphans)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Picker(L10n.graphNodeLimit, selection: $nodeLimit) {
                Text("75").tag(75)
                Text("150").tag(150)
                Text("250").tag(250)
                Text("500").tag(500)
                Text("1000").tag(1000)
            }
            .font(.system(size: 11))
            .accessibilityIdentifier("GraphTab.Limit")
        }
    }

    private var forcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionHeading(L10n.graphForcesSection)
                Spacer(minLength: 0)
                if forces != GraphForces() {
                    Button(L10n.graphResetForces) {
                        withAnimation(.snappy(duration: 0.2)) {
                            centerForce = 1
                            linkDistance = 1
                            linkForce = 1
                            nodeSize = 1
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("GraphTab.ResetForces")
                }
            }

            forceSlider(label: L10n.graphCenterForceSetting, value: $centerForce, range: 0...2)
            forceSlider(label: L10n.graphLinkDistanceSetting, value: $linkDistance, range: 0.25...3)
            forceSlider(label: L10n.graphLinkForceSetting, value: $linkForce, range: 0...2)
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(L10n.graphGroupsSection)

            tagMenu
            folderMenu

            if selectedTag != nil || selectedFolder != nil {
                Button(L10n.clearFilters) {
                    model.clearFilters()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("GraphTab.ClearFilters")
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.45))
            .tracking(0.7)
    }

    private func forceSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer(minLength: 0)
                Text(String(format: "%.2f×", value.wrappedValue))
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .accessibilityLabel(label)
        }
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
        .menuStyle(.borderlessButton)
        .font(.system(size: 11))
        .fixedSize()
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
        .menuStyle(.borderlessButton)
        .font(.system(size: 11))
        .fixedSize()
        .disabled(baseGraph.folders.count < 2)
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
                },
                onSelect: { model.selectedNodeID = $0 }
            )
            .background {
                GlassBackdrop(style: .regular, cornerRadius: 12, interactive: true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: 12))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.25))
                Text(L10n.selectGraphNode)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                GlassBackdrop(style: .regular, cornerRadius: 12, interactive: true)
            }
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func resetFilters() {
        model.resetFilters()
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
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Text(L10n.linkedNotes(node.linkCount))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
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
        .frame(maxHeight: 420)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .tracking(0.6)
            content()
        }
    }

    private func linkSection(_ title: String, nodes: [VaultGraphNode], empty: String) -> some View {
        section(title) {
            if nodes.isEmpty {
                Text(empty)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.3))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(nodes) { linked in
                        Button {
                            onSelect(linked.id)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.45))
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
                            .background(Color.white.opacity(0.12), in: .capsule)
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

/// Filter + selection state for ``GraphTabView``.
///
/// A reference type so every mutation happens through `model` instead of writing
/// `@State` from non-mutating view methods.
@MainActor
final class GraphTabModel: ObservableObject {
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
