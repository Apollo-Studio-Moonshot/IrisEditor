import Foundation

// MARK: - MermaidRenderer

/// A deliberately small parser for Mermaid `flowchart` diagrams. It supports the
/// `flowchart TD` / `flowchart LR` header, `A[Label]` square nodes, `A{Label}` rhombus
/// nodes, `A(Label)` rounded nodes, and `A-->B` / `A-->|text|B` / `A --- B` edges.
///
/// Anything the parser cannot understand returns `nil` so the caller can show a labelled
/// fallback instead of silently dropping the diagram.
enum MermaidParser {

    // MARK: - Flowchart model

    struct Flowchart: Equatable {
        enum Direction: Equatable { case topDown, leftRight }
        let direction: Direction
        let nodes: [Node]
        let edges: [Edge]

        struct Node: Equatable {
            let id: String
            let label: String
        }

        struct Edge: Equatable {
            let from: String
            let to: String
            let label: String
        }
    }

    // MARK: - Public API

    /// Buckets nodes into layout rows (level 0 is the top / left row).
    ///
    /// Cycle-safe by construction: the BFS that seeds the levels touches each node at
    /// most once, and the longest-path relaxation that follows runs for a bounded number
    /// of rounds and refuses to push a level past `nodes.count`. A graph such as
    /// `A --> B; B --> A` therefore lays out in finite time instead of hanging the caller.
    static func levelGroups(_ chart: Flowchart) -> [Int: [String]] {
        var adjacency: [String: [String]] = [:]
        var indegree: [String: Int] = [:]
        for node in chart.nodes {
            adjacency[node.id] = []
            indegree[node.id] = 0
        }
        for edge in chart.edges {
            adjacency[edge.from, default: []].append(edge.to)
            indegree[edge.to, default: 0] += 1
        }

        var level: [String: Int] = [:]
        var queue: [String] = chart.nodes.filter { (indegree[$0.id] ?? 0) == 0 }.map(\.id)
        if queue.isEmpty, let first = chart.nodes.first {
            queue = [first.id]
        }
        for id in queue { level[id] = 0 }

        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for next in adjacency[current] ?? [] where level[next] == nil {
                level[next] = (level[current] ?? 0) + 1
                queue.append(next)
            }
        }

        // Prefer the longest path so join nodes sit below all of their parents. Bounded
        // rounds keep this terminating even when the graph contains a cycle.
        if !chart.edges.isEmpty {
            let rounds = max(1, chart.nodes.count)
            for _ in 0..<rounds {
                var changed = false
                for edge in chart.edges {
                    let candidate = (level[edge.from] ?? 0) + 1
                    if candidate > (level[edge.to] ?? 0), candidate < chart.nodes.count {
                        level[edge.to] = candidate
                        changed = true
                    }
                }
                if !changed { break }
            }
        }

        for node in chart.nodes where level[node.id] == nil {
            level[node.id] = 0
        }

        var grouped: [Int: [String]] = [:]
        for node in chart.nodes {
            grouped[level[node.id] ?? 0, default: []].append(node.id)
        }
        return grouped
    }

    static func flowchart(_ source: String) -> Flowchart? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("%%") }

        guard let first = lines.first else { return nil }

        let direction: Flowchart.Direction
        let body: ArraySlice<String>
        if first.lowercased().hasPrefix("flowchart") {
            let parts = first.split(separator: " ")
            let dir = parts.dropFirst().first?.lowercased() ?? "td"
            direction = (dir == "lr" || dir == "rl") ? .leftRight : .topDown
            body = lines.dropFirst()
        } else if first.lowercased().hasPrefix("graph") {
            let parts = first.split(separator: " ")
            let dir = parts.dropFirst().first?.lowercased() ?? "td"
            direction = (dir == "lr" || dir == "rl") ? .leftRight : .topDown
            body = lines.dropFirst()
        } else {
            direction = .topDown
            body = lines[...]
        }

        var nodes: [String: Flowchart.Node] = [:]
        var edges: [Flowchart.Edge] = []

        for raw in body {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            // Try to split this line into edges. A line like "A-->B-->C" yields two edges.
            // We split on --> and --- and -.-> and ==> etc. For simplicity we recognise
            // only the three most common connectors; anything more complex fails the whole
            // diagram so the preview shows the labelled fallback.
            let connectors: [(String, String)] = [
                ("-->","solid"),
                ("---","thick"),
                ("==>","double"),
                ("-.->","dashed-arrow"),
                ("-.-","dashed")
            ]

            // Build candidate edge first — if we find one, parse; otherwise it's a node.
            var edgeParts: [String] = []
            var edgeLabel = ""
            var matchedConnector: String? = nil
            var remaining = line[...]

            outer: while true {
                // Look for the next connector with optional |label| on either side.
                var bestRange: Range<String.Index>? = nil
                var bestConnector: String? = nil
                for (c, _) in connectors {
                    if let r = remaining.range(of: c) {
                        if bestRange == nil || r.lowerBound < bestRange!.lowerBound {
                            bestRange = r
                            bestConnector = c
                        }
                    }
                }
                guard let range = bestRange, let connector = bestConnector else { break outer }

                // Capture pre-connector text as a node spec, possibly consuming a trailing |label|.
                var prefix = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                // Check for |label| immediately before the connector on the same token
                // — in Mermaid the label is attached to the *edge*, not the node.
                if let pipe = prefix.range(of: #"\|[^|]*\|"#, options: .regularExpression) {
                    let labelPart = prefix[pipe].trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    if edgeLabel.isEmpty { edgeLabel = labelPart }
                    prefix = prefix.replacingOccurrences(of: prefix[pipe], with: "").trimmingCharacters(in: .whitespaces)
                }
                edgeParts.append(prefix)

                remaining = remaining[range.upperBound...]
                if remaining.isEmpty { break outer }
                matchedConnector = connector
            }

            // After collecting the last "to" part, also strip any trailing |label|.
            if let lastPipe = remaining.range(of: #"\|[^|]*\|"#, options: .regularExpression) {
                let labelPart = remaining[lastPipe].trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                if edgeLabel.isEmpty { edgeLabel = labelPart }
                remaining.removeSubrange(lastPipe)
            }
            let lastNode = String(remaining).trimmingCharacters(in: .whitespaces)
            if !lastNode.isEmpty { edgeParts.append(lastNode) }

            if matchedConnector != nil, edgeParts.count >= 2 {
                for i in 0..<edgeParts.count - 1 {
                    let fromSpec = edgeParts[i]
                    let toSpec = edgeParts[i + 1]
                    guard let fromId = parseNodeSpec(fromSpec, into: &nodes),
                          let toId = parseNodeSpec(toSpec, into: &nodes) else {
                        return nil
                    }
                    edges.append(Flowchart.Edge(from: fromId, to: toId, label: edgeLabel))
                }
                continue
            }

            // It's just a node declaration on its own.
            guard parseNodeSpec(line, into: &nodes) != nil else { continue }
        }

        let orderedNodes = nodes.values.sorted { $0.id < $1.id }
        guard !orderedNodes.isEmpty else { return nil }
        return Flowchart(direction: direction, nodes: orderedNodes, edges: edges)
    }

    // MARK: - SVG export

    /// Produces a simple SVG string for the flowchart, suitable for embedding in HTML export.
    static func svg(_ chart: Flowchart) -> String {
        let nodeWidth: CGFloat = 132
        let nodeHeight: CGFloat = 30
        let columnGap: CGFloat = 34
        let rowGap: CGFloat = 58
        let padding: CGFloat = 22

        let levels = levelGroups(chart)
        let maxPerLevel = levels.values.map(\.count).max() ?? 1
        let levelCount = max(1, (levels.keys.max() ?? 0) + 1)
        let isHorizontal = chart.direction == .leftRight

        let width = Int((isHorizontal
            ? CGFloat(levelCount) * (nodeWidth + columnGap) + padding * 2
            : CGFloat(maxPerLevel) * (nodeWidth + columnGap) + padding * 2).rounded())
        let height = Int((isHorizontal
            ? CGFloat(maxPerLevel) * (nodeHeight + rowGap) + padding * 2
            : CGFloat(levelCount) * (nodeHeight + rowGap) + padding * 2).rounded())

        var pos: [String: CGPoint] = [:]
        for (levelIndex, ids) in levels {
            for (index, id) in ids.enumerated() {
                let alongLevel = CGFloat(index) - CGFloat(ids.count - 1) / 2
                if isHorizontal {
                    let x = padding + nodeWidth / 2 + CGFloat(levelIndex) * (nodeWidth + columnGap)
                    let y = CGFloat(height) / 2 + alongLevel * (nodeHeight + rowGap)
                    pos[id] = CGPoint(x: x, y: y)
                } else {
                    let y = padding + nodeHeight / 2 + CGFloat(levelIndex) * (nodeHeight + rowGap)
                    let x = CGFloat(width) / 2 + alongLevel * (nodeWidth + columnGap)
                    pos[id] = CGPoint(x: x, y: y)
                }
            }
        }

        var sb = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n"
        sb += "<defs><marker id=\"arr\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"6\" markerHeight=\"6\" orient=\"auto-start-reverse\"><path d=\"M0,0 L10,5 L0,10 z\" fill=\"#888\" /></marker></defs>\n"

        for edge in chart.edges {
            guard let f = pos[edge.from], let t = pos[edge.to] else { continue }
            sb += "<line x1=\"\(Int(f.x))\" y1=\"\(Int(f.y))\" x2=\"\(Int(t.x))\" y2=\"\(Int(t.y))\" stroke=\"#888\" stroke-width=\"1.2\" marker-end=\"url(#arr)\" />\n"
            if !edge.label.isEmpty {
                let mx = Int((f.x + t.x) / 2)
                let my = Int((f.y + t.y) / 2) - 8
                sb += "<text x=\"\(mx)\" y=\"\(my)\" text-anchor=\"middle\" font-size=\"11\" fill=\"#666\">\(xmlEscape(edge.label))</text>\n"
            }
        }
        for node in chart.nodes {
            guard let p = pos[node.id] else { continue }
            let x = Int(p.x - nodeWidth / 2)
            let y = Int(p.y - nodeHeight / 2)
            sb += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(Int(nodeWidth))\" height=\"\(Int(nodeHeight))\" rx=\"7\" ry=\"7\" fill=\"#2a2d35\" stroke=\"#4a4f5a\" stroke-width=\"0.8\" />\n"
            sb += "<text x=\"\(Int(p.x))\" y=\"\(Int(p.y) + 4)\" text-anchor=\"middle\" font-size=\"12\" fill=\"#eee\">\(xmlEscape(node.label.isEmpty ? node.id : node.label))</text>\n"
        }
        sb += "</svg>"
        return sb
    }

    // MARK: - Internals

    private static func parseNodeSpec(
        _ raw: String,
        into nodes: inout [String: Flowchart.Node]
    ) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let ns = s as NSString

        // id[label]
        if let re = try? NSRegularExpression(pattern: #"^([A-Za-z0-9_]+)\[([^\]]*)\]"#),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range(at: 1))
            let label = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            nodes[id] = Flowchart.Node(id: id, label: label)
            return id
        }
        // id{label}
        if let re = try? NSRegularExpression(pattern: #"^([A-Za-z0-9_]+)\{([^}]*)\}"#),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range(at: 1))
            let label = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            nodes[id] = Flowchart.Node(id: id, label: label)
            return id
        }
        // id(label)
        if let re = try? NSRegularExpression(pattern: #"^([A-Za-z0-9_]+)\(([^)]*)\)"#),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range(at: 1))
            let label = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            nodes[id] = Flowchart.Node(id: id, label: label)
            return id
        }
        // Bare id.
        if let re = try? NSRegularExpression(pattern: #"^([A-Za-z0-9_]+)"#),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range(at: 1))
            if nodes[id] == nil {
                nodes[id] = Flowchart.Node(id: id, label: "")
            }
            return id
        }
        return nil
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
