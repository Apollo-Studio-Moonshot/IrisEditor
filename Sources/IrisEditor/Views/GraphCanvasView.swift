import SwiftUI

// MARK: - Canvas

/// Interactive force-directed graph drawing.
///
/// The view owns presentation state only (viewport + measured layout); the graph data
/// belongs to the caller so the sidebar mini-map and the standalone window can share
/// one renderer at different levels of interactivity.
///
/// Coordinates: node positions from ``GraphLayout`` are in *unzoomed* canvas space.
/// Panning and zooming are applied as a single ``CGAffineTransform`` around the canvas
/// centre, which keeps hit testing and drawing in sync.
///
/// State lives in ``GraphCanvasStore`` (a reference type held by `@StateObject`) so that
/// every gesture and button action mutates through a class reference. Writing
/// `@State`/`@Binding` directly from a `View`'s own methods or closures does not compile
/// here (`'self' is immutable`).
struct GraphCanvasView: View {
    let graph: VaultGraph
    var showsLabels: Bool = true
    var interactive: Bool = true
    @Binding var selectedNodeID: String?

    @StateObject private var store = GraphCanvasStore()

    var body: some View {
        GeometryReader { proxy in
            // Measuring happens here so `canvas(in:)` stays pure; the store no-ops
            // when the graph and size are unchanged.
            let size = proxy.size
            let _ = store.relayout(graph, in: size)
            canvas(in: size, layout: store.layout)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Graph.Canvas")
    }

    // MARK: Composition

    private func canvas(in size: CGSize, layout: GraphLayout) -> some View {
        ZStack(alignment: .topLeading) {
            edgesLayer(layout: layout, transform: store.transform(in: size))
            nodesLayer(layout: layout, transform: store.transform(in: size))
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(interactive ? panGesture(in: size) : nil)
        .simultaneousGesture(interactive ? magnifyGesture : nil)
        .onTapGesture(coordinateSpace: .local) { location in
            guard interactive else { return }
            select(at: location, in: size)
        }
        .overlay(alignment: .bottomTrailing) {
            if interactive {
                zoomControls(size: size)
            }
        }
    }

    // MARK: Layers

    private func edgesLayer(layout: GraphLayout, transform: CGAffineTransform) -> some View {
        Canvas { context, _ in
            for edge in layout.edges {
                var path = Path()
                path.move(to: edge.from.applying(transform))
                path.addLine(to: edge.to.applying(transform))

                let touchesSelection = selectedNodeID != nil
                    && (edge.endpoints.0 == selectedNodeID || edge.endpoints.1 == selectedNodeID)
                let dimmed = selectedNodeID != nil && !touchesSelection
                let color: Color = if touchesSelection || edge.isHighlighted {
                    Color.accentColor.opacity(dimmed ? 0.3 : 0.9)
                } else {
                    Color.primary.opacity(dimmed ? 0.08 : 0.2)
                }
                context.stroke(
                    path,
                    with: .color(color),
                    lineWidth: (touchesSelection ? 1.6 : 1) * min(1.6, max(0.6, transform.a))
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func nodesLayer(layout: GraphLayout, transform: CGAffineTransform) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.nodes) { node in
                nodeView(node, layout: layout, xform: transform)
            }
        }
    }

    private func nodeView(
        _ node: GraphLayout.Node,
        layout: GraphLayout,
        xform: CGAffineTransform
    ) -> some View {
        let selected = selectedNodeID == node.id
        let neighbours = selectedNodeID.map { layout.neighbours(of: $0, in: graph) } ?? []
        let isNeighbour = neighbours.contains(node.id)
        let faded = selectedNodeID != nil && !selected && !isNeighbour && !node.isCurrent
        let center = node.position.applying(xform)
        let radius = node.radius * xform.a
        let dragged = store.viewport.offset(for: node.id)
        let fontSize = Swift.min(11.5, Swift.max(7, 9.5 * xform.a))

        return nodeShape(node, selected: selected, radius: radius, fontSize: fontSize)
            .opacity(faded ? 0.25 : 1)
            .position(x: center.x + dragged.width, y: center.y + dragged.height)
            .animation(.snappy(duration: 0.3), value: center)
            .animation(.easeOut(duration: 0.16), value: radius)
            .allowsHitTesting(false)
            .help(node.title)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(node.title)
            .accessibilityValue(L10n.linkedNotes(node.linkCount))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("Graph.Node.\(node.id)")
    }

    private func nodeShape(
        _ node: GraphLayout.Node,
        selected: Bool,
        radius: CGFloat,
        fontSize: CGFloat
    ) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(fillColor(for: node, selected: selected))
                .frame(width: radius * 2, height: radius * 2)
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color(nsColor: selected ? .controlAccentColor : .separatorColor)
                                .opacity(selected ? 1 : 0.7),
                            lineWidth: selected ? 1.6 : 0.8
                        )
                }
                .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: selected ? 5 : 0)

            if showsLabels || selected {
                Text(node.title)
                    .font(.system(size: fontSize, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 1)
            }
        }
        .frame(width: max(radius * 2, 12))
    }

    private func fillColor(for node: GraphLayout.Node, selected: Bool) -> Color {
        if node.isCurrent { return Color.accentColor.opacity(selected ? 0.95 : 0.8) }
        if selected { return Color.accentColor.opacity(0.85) }
        if node.linkCount == 0 { return Color(nsColor: .tertiaryLabelColor).opacity(0.55) }
        return Color(nsColor: .secondaryLabelColor).opacity(0.85)
    }

    // MARK: Zoom controls

    private func zoomControls(size: CGSize) -> some View {
        HStack(spacing: 4) {
            GraphZoomButtons(store: store)
        }
        .padding(6)
        .background(.thinMaterial, in: .rect(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .padding(10)
        .opacity(size.width > 220 ? 1 : 0)
        .accessibilityIdentifier("Graph.ZoomControls")
    }

    // MARK: Gestures

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                store.viewport.applyPan(value.translation, ended: false)
            }
            .onEnded { value in
                store.viewport.applyPan(value.translation, ended: true)
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                store.viewport.applyMagnification(value.magnification, ended: false)
            }
            .onEnded { _ in
                store.viewport.applyMagnification(1, ended: true)
            }
    }

    private func select(at location: CGPoint, in size: CGSize) {
        // Hit test in layout space: invert the view transform so clicks map back onto
        // the unzoomed node positions.
        let transform = store.transform(in: size)
        let local = location.applying(transform.inverted())
        let tolerance = 8 / max(transform.a, 0.4)
        guard let hit = store.layout.node(at: local, tolerance: tolerance) else {
            selectedNodeID = nil
            return
        }
        selectedNodeID = selectedNodeID == hit.id ? nil : hit.id
    }
}

// MARK: - Store

/// Presentation state for ``GraphCanvasView``: measured layout plus pan / zoom.
///
/// A reference type on purpose — mutating through it keeps view code free of direct
/// `@State` writes, which this codebase cannot rely on (the `State` macro misbehaves
/// under the sandboxed plugin server, and non-mutating view methods reject writes).
@MainActor
final class GraphCanvasStore: ObservableObject {
    @Published var layout = GraphLayout()
    @Published var viewport = GraphViewport()

    private var layoutKey: LayoutKey?

    private struct LayoutKey: Equatable {
        let graph: VaultGraph
        let size: CGSize
    }

    /// Recomputes the force-directed layout when the graph or canvas size changes.
    /// Safe to call from `body`: it no-ops unless the inputs actually changed.
    func relayout(_ graph: VaultGraph, in size: CGSize) {
        let key = LayoutKey(graph: graph, size: size)
        guard key != layoutKey else { return }
        layoutKey = key
        layout = GraphLayoutEngine.layout(graph, in: size)
    }

    func transform(in size: CGSize) -> CGAffineTransform {
        viewport.transform(in: size)
    }

    func zoomIn() {
        viewport.zoom(by: 0.2)
    }

    func zoomOut() {
        viewport.zoom(by: -0.2)
    }

    func resetViewport() {
        withAnimation(.snappy(duration: 0.24)) {
            viewport.reset()
        }
    }
}

// MARK: - Zoom controls

/// Zoom in / out / fit buttons. Actions go through ``GraphCanvasStore`` so the button
/// closures never touch `@State` directly.
private struct GraphZoomButtons: View {
    @ObservedObject var store: GraphCanvasStore

    var body: some View {
        HStack(spacing: 4) {
            Button(action: store.zoomOut) {
                icon("minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.zoomOutGraph)
            .accessibilityLabel(L10n.zoomOutGraph)
            .accessibilityIdentifier("Graph.ZoomOut")

            Button(action: store.zoomIn) {
                icon("plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.zoomInGraph)
            .accessibilityLabel(L10n.zoomInGraph)
            .accessibilityIdentifier("Graph.ZoomIn")

            Button(action: store.resetViewport) {
                icon("arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.graphFit)
            .accessibilityLabel(L10n.graphFit)
            .accessibilityIdentifier("Graph.ZoomFit")
        }
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10.5, weight: .medium))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }
}

// MARK: - Viewport

/// Pan / zoom / node-offset state for ``GraphCanvasView``.
///
/// The pan and magnification transitions live here (rather than as inline writes in the
/// view) so they can be covered by unit tests.
struct GraphViewport: Equatable {
    var zoom: CGFloat = 1
    var committedPan: CGSize = .zero
    var livePan: CGSize = .zero
    var nodeOffsets: [String: CGSize] = [:]

    private var magnifyBase: CGFloat?

    static let minimumZoom: CGFloat = 0.4
    static let maximumZoom: CGFloat = 3.2

    /// Pan plus zoom around the canvas centre: a transform mapping layout space onto
    /// view space.
    func transform(in size: CGSize) -> CGAffineTransform {
        let pan = CGSize(
            width: committedPan.width + livePan.width,
            height: committedPan.height + livePan.height
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGAffineTransform(translationX: center.x + pan.width, y: center.y + pan.height)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -center.x, y: -center.y)
    }

    func offset(for id: String) -> CGSize {
        nodeOffsets[id] ?? .zero
    }

    mutating func applyPan(_ translation: CGSize, ended: Bool) {
        if ended {
            committedPan.width += translation.width
            committedPan.height += translation.height
            livePan = .zero
        } else {
            livePan = translation
        }
    }

    mutating func applyMagnification(_ magnification: CGFloat, ended: Bool) {
        guard !ended else {
            magnifyBase = nil
            return
        }
        // The gesture reports magnification relative to its start; anchor the scale on
        // the first callback so repeated pinch gestures compound correctly.
        let base = magnifyBase ?? zoom
        if magnifyBase == nil {
            magnifyBase = base
        }
        zoom = Self.clamped(base * magnification)
    }

    mutating func zoom(by delta: CGFloat) {
        zoom = Self.clamped(zoom + delta)
    }

    mutating func moveNode(_ id: String, by delta: CGSize) {
        var current = nodeOffsets[id] ?? .zero
        current.width += delta.width
        current.height += delta.height
        nodeOffsets[id] = current
    }

    mutating func reset() {
        self = GraphViewport()
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        Swift.min(maximumZoom, Swift.max(minimumZoom, value))
    }
}
