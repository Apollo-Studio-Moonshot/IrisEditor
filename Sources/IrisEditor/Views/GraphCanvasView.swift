import AppKit
import Foundation
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
/// centre, which keeps hit testing and drawing in sync. Node drags are stored as
/// screen-space offsets so a node follows the pointer at any zoom level.
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

    /// Called when a node is double-clicked, with the node id (a note path).
    var onOpenNode: ((String) -> Void)?

    /// Physics driving the layout; the sidebar mini-map uses the defaults while the
    /// graph tab exposes Obsidian-style sliders.
    var forces: GraphForces = GraphForces()

    /// Obsidian-style immersive rendering: dark depth-gradient backdrop, glowing
    /// nodes and hover dimming. The sidebar mini-map keeps the standard look.
    var immersive: Bool = false

    @StateObject private var store = GraphCanvasStore()
    @State private var hoveredNodeID: String?
    @State private var draggingNodeID: String?
    @State private var nodeDragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            // Measuring happens here so `canvas(in:)` stays pure; the store no-ops
            // when the graph, size and forces are unchanged.
            let size = proxy.size
            let _ = store.relayout(graph, in: size, forces: forces)
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
        .background {
            if immersive {
                immersiveBackdrop
            }
            if interactive {
                // AppKit receives scroll-wheel events before SwiftUI, so a tiny
                // monitor view gives us cursor-anchored scroll-to-zoom.
                GraphScrollWheelMonitor { delta in
                    store.zoomByWheel(delta)
                }
            }
        }
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

    /// Obsidian-style depth backdrop: a soft radial well that keeps the eye centred.
    private var immersiveBackdrop: some View {
        ZStack {
            Color(nsColor: .black)
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.09),
                    Color(nsColor: .black).opacity(0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Layers

    private func edgesLayer(layout: GraphLayout, transform: CGAffineTransform) -> some View {
        // Hovering behaves like selecting: the neighbourhood stays lit, the rest fades.
        let focusID = hoveredNodeID ?? selectedNodeID
        return Canvas { context, _ in
            for edge in layout.edges {
                var path = Path()
                path.move(to: edge.from.applying(transform))
                path.addLine(to: edge.to.applying(transform))

                let touchesFocus = focusID != nil
                    && (edge.endpoints.0 == focusID || edge.endpoints.1 == focusID)
                let dimmed = focusID != nil && !touchesFocus
                let color: Color
                if touchesFocus || (focusID == nil && edge.isHighlighted) {
                    color = Color.accentColor.opacity(dimmed ? 0.3 : 0.9)
                } else if immersive {
                    color = Color.white.opacity(dimmed ? 0.04 : 0.16)
                } else {
                    color = Color.primary.opacity(dimmed ? 0.08 : 0.2)
                }
                context.stroke(
                    path,
                    with: .color(color),
                    lineWidth: (touchesFocus ? 1.6 : 1) * min(1.6, max(0.6, transform.a))
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
        let hovered = hoveredNodeID == node.id
        // Hover previews the neighbourhood the same way a click pins it, like Obsidian.
        let focusID = hoveredNodeID ?? selectedNodeID
        let neighbours = focusID.map { layout.neighbours(of: $0, in: graph) } ?? []
        let isNeighbour = neighbours.contains(node.id)
        let faded = focusID != nil && !selected && !hovered && !isNeighbour && !node.isCurrent
        let center = node.position.applying(xform)
        let radius = node.radius * xform.a
        let dragged = store.viewport.offset(for: node.id)
        let fontSize = Swift.min(11.5, Swift.max(7, 9.5 * xform.a))
        // Labels are always shown when requested, and otherwise fade in on hover or
        // once the user has zoomed in far enough to read them.
        let showLabel = showsLabels || selected || hovered || xform.a >= 1.25

        return nodeShape(
            node,
            selected: selected,
            hovered: hovered,
            radius: radius,
            fontSize: fontSize,
            showLabel: showLabel
        )
        .opacity(faded ? 0.25 : 1)
        .position(x: center.x + dragged.width, y: center.y + dragged.height)
        .animation(.snappy(duration: 0.3), value: center)
        .animation(.easeOut(duration: 0.16), value: radius)
        .allowsHitTesting(interactive)
        .onHover { hovering in
            if hovering {
                hoveredNodeID = node.id
            } else if hoveredNodeID == node.id {
                hoveredNodeID = nil
            }
        }
        // Single-click selection stays on the canvas so background clicks can clear it;
        // only the double-click is handled by the node itself.
        .onTapGesture(count: 2) {
            onOpenNode?(node.id)
        }
        .highPriorityGesture(nodeDragGesture(for: node.id))
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
        hovered: Bool,
        radius: CGFloat,
        fontSize: CGFloat,
        showLabel: Bool
    ) -> some View {
        let fill = fillColor(for: node, selected: selected, hovered: hovered)
        return VStack(spacing: 2) {
            Circle()
                .fill(fill)
                .frame(width: radius * 2, height: radius * 2)
                .overlay {
                    Circle()
                        .strokeBorder(
                            ringColor(selected: selected),
                            lineWidth: selected ? 1.6 : 0.8
                        )
                }
                // Obsidian-style glow: every node carries a soft halo in its own
                // colour; hover and selection turn it up.
                .shadow(color: glowColor(fill, selected: selected, hovered: hovered), radius: glowRadius(selected: selected, hovered: hovered))

            if showLabel {
                Text(node.title)
                    .font(.system(size: fontSize, weight: selected ? .semibold : .regular))
                    .foregroundStyle(labelColor(selected: selected))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 1)
            }
        }
        .frame(width: max(radius * 2, 12))
        .contentShape(.rect)
    }

    private func ringColor(selected: Bool) -> Color {
        if immersive {
            return Color.white.opacity(selected ? 0.9 : 0.18)
        }
        return Color(nsColor: selected ? .controlAccentColor : .separatorColor)
            .opacity(selected ? 1 : 0.7)
    }

    private func glowColor(_ fill: Color, selected: Bool, hovered: Bool) -> Color {
        if immersive {
            if selected || hovered { return fill.opacity(0.9) }
            return fill.opacity(0.45)
        }
        if hovered { return Color.accentColor.opacity(0.45) }
        return .black.opacity(selected ? 0.25 : 0)
    }

    private func glowRadius(selected: Bool, hovered: Bool) -> CGFloat {
        if immersive {
            return selected || hovered ? 12 : 5
        }
        return hovered ? 7 : (selected ? 5 : 0)
    }

    private func labelColor(selected: Bool) -> Color {
        if immersive {
            return Color.white.opacity(selected ? 1 : 0.72)
        }
        return selected ? Color.primary : Color.secondary
    }

    private func fillColor(for node: GraphLayout.Node, selected: Bool, hovered: Bool) -> Color {
        if immersive {
            if node.isCurrent { return Color.accentColor }
            if selected || hovered { return Color.accentColor.opacity(0.92) }
            if node.linkCount == 0 { return Color.white.opacity(0.22) }
            // A calm blue-grey close to Obsidian's default node colour.
            return Color(hue: 0.61, saturation: 0.32, brightness: 0.86).opacity(0.9)
        }
        if node.isCurrent { return Color.accentColor.opacity(selected ? 0.95 : 0.8) }
        if selected { return Color.accentColor.opacity(0.85) }
        if hovered { return Color.accentColor.opacity(0.7) }
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

    /// Moves a node by the incremental part of a global-space drag. Working in global
    /// coordinates keeps the translation stable even though the node itself moves.
    private func nodeDragGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if draggingNodeID != id {
                    draggingNodeID = id
                    nodeDragTranslation = .zero
                }
                let delta = CGSize(
                    width: value.translation.width - nodeDragTranslation.width,
                    height: value.translation.height - nodeDragTranslation.height
                )
                store.viewport.moveNode(id, by: delta)
                nodeDragTranslation = value.translation
            }
            .onEnded { _ in
                draggingNodeID = nil
                nodeDragTranslation = .zero
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
        guard let hit = node(at: location, in: size) else {
            selectedNodeID = nil
            return
        }
        selectedNodeID = selectedNodeID == hit.id ? nil : hit.id
    }

    /// Hit test in layout space: invert the view transform so clicks map back onto
    /// the unzoomed node positions.
    private func node(at location: CGPoint, in size: CGSize) -> GraphLayout.Node? {
        let transform = store.transform(in: size)
        let local = location.applying(transform.inverted())
        let tolerance = 8 / max(transform.a, 0.4)
        return store.layout.node(at: local, tolerance: tolerance)
    }
}

// MARK: - Scroll wheel

/// Installs a local scroll-wheel monitor while the graph is on screen and forwards
/// vertical deltas to the viewport when the pointer is inside this graph.
///
/// A monitor is used because AppKit delivers scroll events to the first responder
/// before SwiftUI gestures, and a transparent overlay view would otherwise swallow
/// clicks and drags meant for the nodes.
private struct GraphScrollWheelMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> GraphScrollWheelView {
        let view = GraphScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: GraphScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: GraphScrollWheelView, coordinator: ()) {
        nsView.stop()
    }
}

/// NSEvent is explicitly non-Sendable; the monitor runs on the main thread, so it is
/// safe to carry the event into `MainActor.assumeIsolated` in this small box.
private struct UncheckedEvent: @unchecked Sendable {
    let event: NSEvent
}

private final class GraphScrollWheelView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let box = UncheckedEvent(event: event)
            let consumed = MainActor.assumeIsolated { self.handle(box.event) }
            return consumed ? nil : event
        }
    }

    /// Returns `true` when the event was over this graph and should not propagate.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let onScroll else { return false }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else { return false }
        onScroll(delta)
        return true
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
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
        let forces: GraphForces
    }

    /// Recomputes the force-directed layout when the graph, canvas size or forces
    /// change. Safe to call from `body`: it no-ops unless the inputs actually changed.
    func relayout(_ graph: VaultGraph, in size: CGSize, forces: GraphForces = GraphForces()) {
        let key = LayoutKey(graph: graph, size: size, forces: forces)
        guard key != layoutKey else { return }
        layoutKey = key
        layout = GraphLayoutEngine.layout(graph, in: size, forces: forces)
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

    func zoomByWheel(_ delta: CGFloat) {
        viewport.zoom(byWheelDelta: delta)
    }

    /// Fits the automatic layout back into view without discarding manual node drags.
    func fitToView() {
        withAnimation(.snappy(duration: 0.24)) {
            viewport.fit()
        }
    }

    /// Restores the viewport and every dragged node to their automatic positions.
    func resetViewport() {
        withAnimation(.snappy(duration: 0.24)) {
            viewport.reset()
        }
    }
}

// MARK: - Zoom controls

/// Zoom in / out / fit / reset buttons. Actions go through ``GraphCanvasStore`` so the
/// button closures never touch `@State` directly.
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

            Button(action: store.fitToView) {
                icon("arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.graphFit)
            .accessibilityLabel(L10n.graphFit)
            .accessibilityIdentifier("Graph.ZoomFit")

            Button(action: store.resetViewport) {
                icon("arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.graphReset)
            .accessibilityLabel(L10n.graphReset)
            .accessibilityIdentifier("Graph.ZoomReset")
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

    /// Exponential scroll-wheel zoom. Positive deltas (scroll up) zoom in.
    mutating func zoom(byWheelDelta delta: CGFloat) {
        let factor = exp(delta * 0.01)
        zoom = Self.clamped(zoom * factor)
    }

    mutating func moveNode(_ id: String, by delta: CGSize) {
        var current = nodeOffsets[id] ?? .zero
        current.width += delta.width
        current.height += delta.height
        nodeOffsets[id] = current
    }

    /// Puts the viewport back to 100% with no pan, keeping manual node positions.
    mutating func fit() {
        zoom = 1
        committedPan = .zero
        livePan = .zero
        magnifyBase = nil
    }

    mutating func reset() {
        self = GraphViewport()
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        Swift.min(maximumZoom, Swift.max(minimumZoom, value))
    }
}
