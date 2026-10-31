import CoreGraphics
import Foundation
import Testing
@testable import IrisEditor

/// Covers the graph data model, the force-directed layout, the pan / zoom viewport and
/// the starred-note store that back the sidebar and graph window.
@Suite("Graph and sidebar workspace")
struct GraphWorkspaceTests {

    // MARK: Fixtures

    private func file(_ path: String, modified: Date = Date(timeIntervalSince1970: 0)) -> VaultFile {
        VaultFile(
            url: URL(fileURLWithPath: "/vault/\(path)"),
            name: (path as NSString).lastPathComponent,
            title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
            relativePath: path,
            modified: modified
        )
    }

    /// Writes a small vault to a temporary directory and returns its root.
    private func makeVault(_ notes: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("IrisGraphTests-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in notes {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func graph(_ nodes: [VaultGraphNode], _ edges: [(String, String)]) -> VaultGraph {
        VaultGraph(
            nodes: nodes,
            edges: edges.map { VaultGraphEdge(source: $0.0, target: $0.1) }
        )
    }

    private func node(
        _ id: String,
        title: String? = nil,
        folder: String = "",
        isCurrent: Bool = false,
        linkCount: Int = 1,
        tags: [String] = []
    ) -> VaultGraphNode {
        VaultGraphNode(
            id: id,
            title: title ?? id,
            folder: folder,
            isCurrent: isCurrent,
            linkCount: linkCount,
            tags: tags
        )
    }

    // MARK: Graph model

    @Test func graphCollectsDistinctFoldersAndTags() {
        let value = graph(
            [
                node("/v/A.md", folder: "", tags: ["idea", "later"]),
                node("/v/Sub/B.md", folder: "Sub", tags: ["idea"]),
                node("/v/Sub/Deep/C.md", folder: "Sub/Deep")
            ],
            []
        )

        #expect(value.folders == ["", "Sub", "Sub/Deep"])
        #expect(value.tags == ["idea", "later"])
    }

    @Test func removingNodesDropsTheirEdges() {
        let value = graph([node("a"), node("b"), node("c")], [("a", "b"), ("b", "c")])

        let pruned = value.removing(nodesIDs: ["a"])

        #expect(pruned.nodes.map(\.id) == ["b", "c"])
        #expect(pruned.edges.map(\.id) == ["b->c"])
    }

    @Test func removingNoNodesIsANoOp() {
        let value = graph([node("a")], [])
        #expect(value.removing(nodesIDs: []) == value)
    }

    // MARK: Scanner

    @Test func scannerResolvesWikiLinksTagsAndFolders() throws {
        let root = try makeVault([
            "Home.md": "# Home\n\nSee [[Alpha]] and [[Sub/Beta|beta]].\n\n#project #later",
            "Alpha.md": "# Alpha\n\nBack to [[Home]].\n\n#project",
            "Sub/Beta.md": "# Beta\n\n#other",
            "Lonely.md": "no links here"
        ])

        let files = VaultScanner.markdownFiles(in: root)
        let result = VaultScanner.graph(around: nil, in: files, limit: 10)

        #expect(result.nodes.count == 4)

        let home = try #require(result.nodes.first { $0.title == "Home" })
        #expect(home.tags.sorted() == ["later", "project"])
        #expect(!home.isCurrent)
        // Every directed link touching the note counts, so Home reaches 3 through
        // Home → Alpha, Home → Beta and Alpha → Home.
        #expect(home.linkCount == 3)

        let alpha = try #require(result.nodes.first { $0.title == "Alpha" })
        #expect(alpha.linkCount == 2)

        let beta = try #require(result.nodes.first { $0.title == "Beta" })
        #expect(beta.folder == "Sub")
        #expect(beta.tags == ["other"])

        #expect(VaultScanner.relativeDirectory(of: root.appendingPathComponent("Sub/Beta.md"), in: root) == "Sub")
    }

    @Test func scannerHonorsTheNodeLimit() throws {
        var notes: [String: String] = [:]
        for index in 0..<12 {
            notes["Note\(index).md"] = "# Note\(index)\n"
        }
        let root = try makeVault(notes)
        let files = VaultScanner.markdownFiles(in: root)

        #expect(VaultScanner.graph(around: nil, in: files, limit: 5).nodes.count == 5)
        #expect(VaultScanner.graph(around: nil, in: files, limit: 0) == .empty)
        #expect(VaultScanner.graph(around: nil, in: [], limit: 10) == .empty)
    }

    @Test func scannerDropsSelfLinks() throws {
        let root = try makeVault([
            "Self.md": "Pointing at [[Self]] and [[Other]]",
            "Other.md": "nothing"
        ])
        let files = VaultScanner.markdownFiles(in: root)
        let result = VaultScanner.graph(around: nil, in: files)

        #expect(result.edges.count == 1)
        #expect(result.nodes.allSatisfy { $0.linkCount == 1 })
    }

    @Test func localGraphWalkRespectsDepth() throws {
        let root = try makeVault([
            "Home.md": "[[One]]",
            "One.md": "[[Two]]",
            "Two.md": "[[Three]]",
            "Three.md": "end"
        ])
        let files = VaultScanner.markdownFiles(in: root)
        let home = root.appendingPathComponent("Home.md")

        let shallow = VaultScanner.graph(around: home, in: files, depth: 1)
        #expect(Set(shallow.nodes.map(\.title)) == ["Home", "One"])
        #expect(shallow.nodes.first { $0.isCurrent }?.title == "Home")

        let deeper = VaultScanner.graph(around: home, in: files, depth: 2, highlighting: home)
        #expect(Set(deeper.nodes.map(\.title)) == ["Home", "One", "Two"])
        #expect(deeper.nodes.first { $0.isCurrent }?.title == "Home")
    }

    // MARK: Layout

    @Test func layoutKeepsEveryNodeInsideTheCanvas() {
        let value = graph(
            (0..<12).map { node("N\($0)") },
            (0..<11).map { ("N\($0)", "N\($0 + 1)") } + [("N0", "N6"), ("N3", "N9")]
        )
        let size = CGSize(width: 400, height: 300)
        let layout = GraphLayoutEngine.layout(value, in: size)

        #expect(layout.nodes.count == 12)
        #expect(layout.edges.count == 13)
        for layoutNode in layout.nodes {
            #expect(layoutNode.position.x >= 0 && layoutNode.position.x <= size.width)
            #expect(layoutNode.position.y >= 0 && layoutNode.position.y <= size.height)
        }
    }

    @Test func layoutPinsTheCurrentNoteToTheCentre() {
        let value = graph(
            [node("centre", isCurrent: true), node("a"), node("b")],
            [("centre", "a"), ("centre", "b")]
        )
        let size = CGSize(width: 320, height: 240)
        let layout = GraphLayoutEngine.layout(value, in: size)

        let centre = layout.nodes.first { $0.id == "centre" }
        #expect(centre?.position.x == size.width / 2)
        #expect(centre?.position.y == size.height / 2)
    }

    @Test func layoutGivesHubsALargerRadius() {
        let value = graph(
            [node("hub", linkCount: 6), node("leaf", linkCount: 0)],
            [("hub", "leaf")]
        )
        let layout = GraphLayoutEngine.layout(value, in: CGSize(width: 300, height: 300))

        let hub = try? #require(layout.nodes.first { $0.id == "hub" })
        let leaf = try? #require(layout.nodes.first { $0.id == "leaf" })
        #expect((hub?.radius ?? 0) >= (leaf?.radius ?? 0))
    }

    @Test func layoutOfAnEmptyGraphIsEmpty() {
        let layout = GraphLayoutEngine.layout(.empty, in: CGSize(width: 100, height: 100))
        #expect(layout.nodes.isEmpty)
        #expect(layout.edges.isEmpty)
    }

    @Test func hitTestingFindsNodesNearThePoint() throws {
        let value = graph([node("a"), node("b")], [("a", "b")])
        let layout = GraphLayoutEngine.layout(value, in: CGSize(width: 300, height: 200))
        let target = try #require(layout.nodes.first)

        #expect(layout.node(at: target.position, tolerance: 4)?.id == target.id)
        #expect(layout.node(at: CGPoint(x: -500, y: -500), tolerance: 4) == nil)
    }

    @Test func neighboursCoverBothDirections() {
        let value = graph([node("a"), node("b"), node("c")], [("a", "b")])
        let layout = GraphLayoutEngine.layout(value, in: CGSize(width: 200, height: 200))

        #expect(layout.neighbours(of: "a", in: value) == ["b"])
        #expect(layout.neighbours(of: "b", in: value) == ["a"])
        #expect(layout.neighbours(of: "c", in: value).isEmpty)
    }

    @Test func labelOpacityShrinksAsTheGraphGrows() {
        let value = graph((0..<3).map { node("N\($0)") }, [])
        let layout = GraphLayoutEngine.layout(value, in: CGSize(width: 200, height: 200))

        #expect(layout.labelOpacity(for: 3) > layout.labelOpacity(for: 500))
    }

    // MARK: Viewport

    @Test func viewportClampsZoom() {
        var viewport = GraphViewport()
        viewport.zoom(by: 10)
        #expect(viewport.zoom == GraphViewport.maximumZoom)

        viewport.zoom(by: -20)
        #expect(viewport.zoom == GraphViewport.minimumZoom)
    }

    @Test func viewportCommitsPanOnEnd() {
        var viewport = GraphViewport()
        viewport.applyPan(CGSize(width: 30, height: -10), ended: false)
        #expect(viewport.livePan.width == 30)
        #expect(viewport.committedPan == .zero)

        viewport.applyPan(CGSize(width: 30, height: -10), ended: true)
        #expect(viewport.livePan == .zero)
        #expect(viewport.committedPan.width == 30)
        #expect(viewport.committedPan.height == -10)
    }

    @Test func magnificationAnchorsOnTheFirstCallback() {
        var viewport = GraphViewport()
        viewport.applyMagnification(2, ended: false)
        #expect(viewport.zoom == 2)

        // The gesture keeps reporting relative to its start, so 1.5 means "1.5× the
        // original", not "3×".
        viewport.applyMagnification(1.5, ended: false)
        #expect(viewport.zoom == 1.5)

        viewport.applyMagnification(1, ended: true)
        viewport.applyMagnification(2, ended: false)
        #expect(viewport.zoom == 3)
    }

    @Test func transformMapsTheCanvasCentreOntoItself() {
        var viewport = GraphViewport()
        let size = CGSize(width: 200, height: 100)
        let centre = CGPoint(x: 100, y: 50)

        #expect(centre.applying(viewport.transform(in: size)) == centre)

        viewport.zoom(by: 1)
        viewport.applyPan(CGSize(width: 20, height: 5), ended: true)
        #expect(centre.applying(viewport.transform(in: size)) == CGPoint(x: 120, y: 55))
    }

    @Test func resetRestoresTheDefaultViewport() {
        var viewport = GraphViewport()
        viewport.zoom(by: 1)
        viewport.applyPan(CGSize(width: 40, height: 40), ended: true)
        viewport.moveNode("a", by: CGSize(width: 5, height: 5))

        viewport.reset()

        #expect(viewport == GraphViewport())
    }

    @Test func movingANodeAccumulatesOffsets() {
        var viewport = GraphViewport()
        viewport.moveNode("a", by: CGSize(width: 4, height: 2))
        viewport.moveNode("a", by: CGSize(width: 1, height: 1))

        #expect(viewport.offset(for: "a") == CGSize(width: 5, height: 3))
        #expect(viewport.offset(for: "b") == .zero)
    }

    // MARK: Bookmarks

    @Test func bookmarkStoreAddsRemovesAndDeduplicates() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let vault = URL(fileURLWithPath: "/vault")

        var bookmarks = BookmarkStore.adding(
            VaultBookmark(url: url, vaultRoot: vault, title: "Note", added: Date()),
            to: []
        )
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].title == "Note")
        #expect(bookmarks[0].id == "/vault/Note.md")

        bookmarks = BookmarkStore.adding(
            VaultBookmark(url: url, vaultRoot: vault, title: "Renamed", added: Date()),
            to: bookmarks
        )
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].title == "Renamed")

        #expect(BookmarkStore.contains(url, in: vault, in: bookmarks))
        #expect(!BookmarkStore.contains(URL(fileURLWithPath: "/vault/Other.md"), in: vault, in: bookmarks))
        #expect(!BookmarkStore.contains(url, in: URL(fileURLWithPath: "/elsewhere"), in: bookmarks))
        #expect(!BookmarkStore.contains(nil, in: vault, in: bookmarks))

        #expect(BookmarkStore.removing(url, from: bookmarks).isEmpty)
    }

    @Test func bookmarkReportsItsFolderAndMatchesStandardizedPaths() {
        let bookmark = VaultBookmark(
            url: URL(fileURLWithPath: "/vault/Sub/Note.md"),
            vaultRoot: URL(fileURLWithPath: "/vault"),
            title: "Note",
            added: Date(timeIntervalSince1970: 0)
        )

        #expect(bookmark.folder == "Sub")
        let vault = URL(fileURLWithPath: "/vault")
        #expect(bookmark.matches(URL(fileURLWithPath: "/vault/Sub/./Note.md"), in: vault))
        #expect(!bookmark.matches(URL(fileURLWithPath: "/vault/Sub/Other.md"), in: vault))
        // A bookmark saved in a vault does not light up when no vault is active.
        #expect(!bookmark.matches(URL(fileURLWithPath: "/vault/Sub/Note.md"), in: nil))
    }

    @Test func pruningDropsMissingNotes() throws {
        let root = try makeVault(["Here.md": "# Here"])
        let present = root.appendingPathComponent("Here.md")
        let missing = root.appendingPathComponent("Gone.md")
        let bookmarks = [present, missing].reduce(into: [VaultBookmark]()) { partial, url in
            partial = BookmarkStore.adding(
                VaultBookmark(url: url, vaultRoot: root, title: url.lastPathComponent, added: Date()),
                to: partial
            )
        }

        let pruned = BookmarkStore.prune(bookmarks)

        #expect(pruned.count == 1)
        #expect(pruned[0].url.lastPathComponent == "Here.md")
    }

    // MARK: Sidebar helpers

    @Test func relativeDirectoryIsEmptyForRootNotes() {
        let root = URL(fileURLWithPath: "/vault")
        #expect(VaultScanner.relativeDirectory(of: root.appendingPathComponent("A.md"), in: root) == "")
        #expect(
            VaultScanner.relativeDirectory(of: root.appendingPathComponent("A/B/C.md"), in: root) == "A/B"
        )
    }

    @Test func queryOperatorsCoverContentAndTitle() {
        let byContent = VaultQuery.parse("content:needle tag:idea")
        #expect(byContent.contentFragments == ["needle"])
        #expect(byContent.tags == ["idea"])

        let byTitle = VaultQuery.parse("title:index")
        #expect(byTitle.nameFragments == ["index"])

        // Negated content: filters are not "not containing" — they are ignored.
        #expect(VaultQuery.parse("-content:needle").contentFragments.isEmpty)
    }

    @Test func listingAndSortModesAreDistinct() {
        #expect(Set(VaultFileListing.allCases.map(\.title)).count == VaultFileListing.allCases.count)
        #expect(Set(VaultFileSort.allCases.map(\.title)).count == VaultFileSort.allCases.count)
        #expect(GraphScope.allCases == [.local, .vault])
        #expect(GraphScope.vault.title == L10n.vaultGraph)
        #expect(GraphScope.local.title == L10n.localGraph)
    }

    @Test func filesPaneOrderingIsStable() {
        let older = file("Beta.md", modified: Date(timeIntervalSince1970: 10))
        let newer = file("Alpha.md", modified: Date(timeIntervalSince1970: 20))

        let byName = [older, newer].sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        #expect(byName.map(\.name) == ["Alpha.md", "Beta.md"])

        let byDate = [older, newer].sorted { $0.modified > $1.modified }
        #expect(byDate.map(\.name) == ["Alpha.md", "Beta.md"])
    }
}
