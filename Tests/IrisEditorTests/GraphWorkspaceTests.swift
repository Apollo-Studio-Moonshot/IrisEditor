import Foundation
import Testing
@testable import IrisEditor

/// Covers the starred-note store and the sidebar helpers that back the vault workspace.
@Suite("Vault sidebar workspace")
struct VaultSidebarTests {

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
            .appendingPathComponent("IrisSidebarTests-\(UUID().uuidString)", isDirectory: true)
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
    }

    @Test func filesPaneOrderingIsStable() {
        let alpha = file("Alpha.md", modified: Date(timeIntervalSince1970: 10))
        let beta = file("Beta.md", modified: Date(timeIntervalSince1970: 10))
        let files = [beta, alpha]

        #expect(VaultScanner.sorted(files, by: .name, ascending: true).map(\.name) == ["Alpha.md", "Beta.md"])
        #expect(VaultScanner.sorted(files, by: .modified, ascending: false).map(\.name) == ["Beta.md", "Alpha.md"])
        #expect(VaultScanner.sorted(files, by: .modified, ascending: true).map(\.name) == ["Alpha.md", "Beta.md"])
    }
}
