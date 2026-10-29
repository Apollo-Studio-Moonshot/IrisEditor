import Foundation
import Testing
@testable import IrisEditor

/// Covers the Obsidian-style operators accepted by the vault search field.
@Suite("Vault query operators")
struct VaultQueryTests {

    private func file(_ path: String) -> VaultFile {
        VaultFile(
            url: URL(fileURLWithPath: "/vault/\(path)"),
            name: (path as NSString).lastPathComponent,
            title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
            relativePath: path,
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func plainTextQuery() {
        let query = VaultQuery.parse("alpha beta")
        #expect(query.text == "alpha beta")
        #expect(query.tags.isEmpty)
        #expect(!query.matchCase)
    }

    @Test func tagOperatorAcceptsHashPrefix() {
        #expect(VaultQuery.parse("tag:#idea").tags == ["idea"])
        #expect(VaultQuery.parse("tag:idea").tags == ["idea"])
        #expect(VaultQuery.parse("tag:idea needles").text == "needles")
    }

    @Test func negationOperators() {
        let query = VaultQuery.parse("-tag:archive -path:trash note")
        #expect(query.excludedTags == ["archive"])
        #expect(query.excludedPathFragments == ["trash"])
        #expect(query.text == "note")
    }

    @Test func quotedValuesStayTogether() {
        let query = VaultQuery.parse("tag:\"needs review\" body")
        #expect(query.tags == ["needs review"])
        #expect(query.text == "body")
    }

    @Test func unknownOperatorStaysText() {
        // `time: 10` is not an operator, so it must still be searchable text.
        let query = VaultQuery.parse("time:10 value")
        #expect(query.tags.isEmpty)
        #expect(query.text == "time:10 value")
    }

    @Test func emptyQueryIsEmpty() {
        #expect(VaultQuery.parse("   ").isEmpty)
        #expect(!VaultQuery.parse("x").isEmpty)
    }

    @Test func pathAndNameFilters() {
        let query = VaultQuery.parse("path:daily file:2026")
        #expect(query.matchesFile(file("daily/2026-10-29.md")))
        #expect(!query.matchesFile(file("weekly/2026-10-29.md")))
        #expect(!query.matchesFile(file("daily/2025-01-01.md")))
    }

    @Test func excludedPathFilters() {
        let query = VaultQuery.parse("-path:archive")
        #expect(query.matchesFile(file("notes/a.md")))
        #expect(!query.matchesFile(file("archive/a.md")))
    }

    @Test func tagFilterReadsInlineTags() {
        let query = VaultQuery.parse("tag:idea")
        #expect(query.matchesMetadata(of: "# idea\n\nsome #idea here"))
        #expect(!query.matchesMetadata(of: "# note\n\nno tags"))
    }

    @Test func tagFilterMatchesNestedTags() {
        let query = VaultQuery.parse("tag:project")
        #expect(query.matchesMetadata(of: "#project/iris is on track"))
        #expect(!query.matchesMetadata(of: "#projects everywhere"))
    }

    @Test func excludedTagFilter() {
        let query = VaultQuery.parse("-tag:archive")
        #expect(query.matchesMetadata(of: "#work item"))
        #expect(!query.matchesMetadata(of: "#archive old"))
    }

    @Test func searchHonoursTagFilterAndReturnsFileLevelHit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-query-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tagged = directory.appendingPathComponent("idea.md")
        try "#idea\nThe actual idea\n".write(to: tagged, atomically: true, encoding: .utf8)
        let plain = directory.appendingPathComponent("plain.md")
        try "Nothing tagged here\n".write(to: plain, atomically: true, encoding: .utf8)

        let files = VaultScanner.markdownFiles(in: directory)
        let results = VaultScanner.search("tag:idea", in: files)
        #expect(results.count == 1)
        #expect(results.first?.title == "idea")
    }

    @Test func searchHonoursMatchCase() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-case-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("note.md")
        try? "Hello World\nhello again\n".write(to: url, atomically: true, encoding: .utf8)
        let files = VaultScanner.markdownFiles(in: directory)

        #expect(VaultScanner.search("hello", in: files).count == 2)
        #expect(VaultScanner.search("match-case: hello", in: files).count == 1)
    }
}
