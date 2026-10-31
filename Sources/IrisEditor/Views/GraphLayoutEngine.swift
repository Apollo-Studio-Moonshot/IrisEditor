import SwiftUI

// MARK: - Layout

/// A laid-out graph: where every node sits and how edges are drawn.
///
/// The layout is deterministic for a given graph and size so that the canvas only
/// animates when the data really changed, not on every redraw.
public struct GraphLayout {
    struct Node: Identifiable {
        let id: String
        let title: String
        let folder: String
        let tags: [String]
        let isCurrent: Bool
        let linkCount: Int
        let position: CGPoint
        let radius: CGFloat
    }

    struct Edge: Identifiable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        /// Endpoint node ids, used for selection-aware drawing.
        let endpoints: (String, String)
        /// Edges touching the focused note are drawn brighter.
        let isHighlighted: Bool

        static func == (lhs: Edge, rhs: Edge) -> Bool { lhs.id == rhs.id }
    }

    var nodes: [Node] = []
    var edges: [Edge] = []

    /// How labels collide: fade them out as the graph gets denser.
    func labelOpacity(for nodeCount: Int) -> Double {
        switch nodeCount {
        case ...12: 1
        case ...30: 0.85
        case ...60: 0.6
        default: 0.35
        }
    }

    /// The node under `point`, if any, searching the nearest node within its radius.
    func node(at point: CGPoint, tolerance: CGFloat = 6) -> Node? {
        nodes
            .map { ($0, hypot($0.position.x - point.x, $0.position.y - point.y)) }
            .filter { $0.1 <= $0.0.radius + tolerance }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Node ids directly connected to `id`.
    func neighbours(of id: String, in graph: VaultGraph) -> Set<String> {
        var result: Set<String> = []
        for edge in graph.edges {
            if edge.source == id {
                result.insert(edge.target)
            } else if edge.target == id {
                result.insert(edge.source)
            }
        }
        result.remove(id)
        return result
    }
}

// MARK: - Layout engine

/// Deterministic force-directed layout (Fruchterman–Reingold style pressure with a
/// gravity well toward the centre). Pure function of the input, so it can be exercised
/// from tests and cached by the view.
public enum GraphLayoutEngine {
    static func layout(
        _ graph: VaultGraph,
        in size: CGSize,
        iterations: Int = 220
    ) -> GraphLayout {
        guard !graph.nodes.isEmpty, size.width > 1, size.height > 1 else {
            return GraphLayout()
        }

        let count = graph.nodes.count
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let usable = CGSize(width: size.width - 44, height: size.height - 44)
        let areas = max(1, Double(usable.width * usable.height))
        let ideal = sqrt(areas / Double(count))
        let maxRadius = Double(min(usable.width, usable.height)) / 2
        var positions = initialPositions(
            graph: graph,
            center: center,
            radius: maxRadius,
            ideal: ideal
        )

        let indexByID = Dictionary(
            uniqueKeysWithValues: graph.nodes.enumerated().map { ($0.element.id, $0.offset) }
        )
        let edges: [(Int, Int)] = graph.edges.compactMap { edge in
            guard let from = indexByID[edge.source], let to = indexByID[edge.target], from != to else {
                return nil
            }
            return (from, to)
        }
        let pinned = graph.nodes.firstIndex { $0.isCurrent }

        guard count > 1 else {
            let node = graph.nodes[0]
            return GraphLayout(
                nodes: [makeNode(node, at: center, count: count)],
                edges: []
            )
        }

        var temperature = maxRadius / 2
        let cooling = Double(iterations) > 0
            ? pow(0.02 / max(temperature, 0.001), 1.0 / Double(iterations))
            : 1
        var displacements = Array(repeating: CGPoint.zero, count: count)

        for _ in 0..<iterations {
            for index in 0..<count { displacements[index] = CGPoint.zero }

            // Repulsion between every pair.
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var dx = positions[i].x - positions[j].x
                    var dy = positions[i].y - positions[j].y
                    var distance = hypot(dx, dy)
                    if distance < 0.01 {
                        // Coincident nodes get a deterministic nudge so the layout stays stable.
                        dx = Double((i &* 7 &+ j &* 13) % 11 - 5) * 0.1 + 0.01
                        dy = Double((i &* 5 &+ j &* 3) % 13 - 6) * 0.1 + 0.01
                        distance = hypot(dx, dy)
                    }
                    let force = ideal * ideal / max(distance, 0.01)
                    let fx = dx / distance * force
                    let fy = dy / distance * force
                    displacements[i].x += fx
                    displacements[i].y += fy
                    displacements[j].x -= fx
                    displacements[j].y -= fy
                }
            }

            // Attraction along edges, stronger than repulsion so clusters pull together.
            for (from, to) in edges {
                var dx = positions[from].x - positions[to].x
                var dy = positions[from].y - positions[to].y
                let distance = hypot(dx, dy)
                guard distance > 0.01 else { continue }
                let force = distance * distance / ideal
                dx = dx / distance * force
                dy = dy / distance * force
                displacements[from].x -= dx
                displacements[from].y -= dy
                displacements[to].x += dx
                displacements[to].y += dy
            }

            // Gravity toward the centre keeps isolated notes from flying off.
            for index in 0..<count {
                let dx = center.x - positions[index].x
                let dy = center.y - positions[index].y
                let distance = hypot(dx, dy)
                guard distance > 0.01 else { continue }
                let force = distance * ideal * 0.045
                displacements[index].x += dx / distance * force
                displacements[index].y += dy / distance * force
            }

            for index in 0..<count {
                let dx = displacements[index].x
                let dy = displacements[index].y
                let length = hypot(dx, dy)
                guard length > 0.01 else { continue }
                let step = min(length, temperature)
                var next = CGPoint(
                    x: positions[index].x + dx / length * step,
                    y: positions[index].y + dy / length * step
                )
                // Keep nodes inside the padded box.
                next.x = min(max(next.x, 18), size.width - 18)
                next.y = min(max(next.y, 18), size.height - 18)
                positions[index] = next
            }

            // The focused note stays put so the eye can track it between refreshes.
            if let pinned {
                positions[pinned] = center
            }
            temperature *= cooling
        }

        var nodes: [GraphLayout.Node] = []
        nodes.reserveCapacity(count)
        for (index, node) in graph.nodes.enumerated() {
            nodes.append(makeNode(node, at: positions[index], count: count))
        }

        let layoutEdges = edges.map { pair in
            GraphLayout.Edge(
                id: "\(graph.nodes[pair.0].id)->\(graph.nodes[pair.1].id)",
                from: positions[pair.0],
                to: positions[pair.1],
                endpoints: (graph.nodes[pair.0].id, graph.nodes[pair.1].id),
                isHighlighted: graph.nodes[pair.0].isCurrent || graph.nodes[pair.1].isCurrent
            )
        }

        return GraphLayout(nodes: nodes, edges: layoutEdges)
    }

    /// Seeds nodes on a golden-angle spiral: deterministic, and spread enough that the
    /// first repulsion pass does not need hundreds of iterations to untangle.
    private static func initialPositions(
        graph: VaultGraph,
        center: CGPoint,
        radius: Double,
        ideal: Double
    ) -> [CGPoint] {
        let count = graph.nodes.count
        guard count > 1 else { return [center] }
        let goldenAngle = Double.pi * (3 - sqrt(5))
        let spread = max(ideal, 8)
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let node = graph.nodes[index]
            if node.isCurrent {
                result.append(center)
                continue
            }
            let distance = min(spread * sqrt(Double(index + 1)) * 1.6, radius)
            let angle = Double(index) * goldenAngle
            result.append(CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance
            ))
        }
        return result
    }

    private static func makeNode(
        _ node: VaultGraphNode,
        at point: CGPoint,
        count: Int
    ) -> GraphLayout.Node {
        // Hubs grow slightly, but never enough to swallow their neighbours.
        let radius: CGFloat
        if node.isCurrent {
            radius = 9
        } else {
            let growth = min(3.5, CGFloat(node.linkCount) * 0.55)
            radius = (count > 80 ? 3.2 : count > 30 ? 4.2 : 5) + growth
        }
        return GraphLayout.Node(
            id: node.id,
            title: node.title,
            folder: node.folder,
            tags: node.tags,
            isCurrent: node.isCurrent,
            linkCount: node.linkCount,
            position: point,
            radius: radius
        )
    }
}
