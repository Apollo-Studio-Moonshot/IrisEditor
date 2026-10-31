import Foundation
import Testing
@testable import IrisEditor

/// Footnotes, `![[…]]` transclusions, unlinked mentions, and the HTML export that
/// mirrors them.
@Suite("Transclusion and mentions")
struct TransclusionAndMentionsTests {

    // MARK: - Footnotes

    @Test func footnoteDefinitionsAreCollectedAndExcludedFromBlocks() {
        let markdown = """
        Body text with a reference.[^1]

        [^1]: The footnote body.
        """
        let document = MarkdownBlockParser.parseDocument(markdown)

        #expect(document.footnotes.count == 1)
        #expect(document.footnotes.first?.label == "1")
        #expect(document.footnotes.first?.text == "The footnote body.")
        #expect(document.blocks.allSatisfy { block in
            if case .paragraph(let text) = block { return !text.contains("[^1]:") }
            return true
        })
    }

    @Test func footnoteNumbersFollowReferenceOrder() {
        let markdown = """
        Two refs.[^b] and one.[^a]

        [^a]: A
        [^b]: B
        """
        let document = MarkdownBlockParser.parseDocument(markdown)
        let numbers = MarkdownFootnoteIndex.numbers(in: document)

        #expect(numbers["b"] == 1)
        #expect(numbers["a"] == 2)
        let ordered = MarkdownFootnoteIndex.orderedFootnotes(for: document)
        #expect(ordered.map(\.footnote.label) == ["b", "a"])
    }

    @Test func unreferencedFootnoteIsNotNumbered() {
        let document = MarkdownBlockParser.parseDocument(
            """
            No reference here.

            [^orphan]: never used
            """
        )
        #expect(MarkdownFootnoteIndex.numbers(in: document).isEmpty)
        #expect(MarkdownFootnoteIndex.orderedFootnotes(for: document).isEmpty)
    }

    @Test func footnoteContinuationLinesStayInTheDefinition() {
        let document = MarkdownBlockParser.parseDocument(
            """
            Text[^n]

            [^n]: first line
                second line
            """
        )
        #expect(document.footnotes.first?.text == "first line\nsecond line")
    }

    @Test func footnoteReferenceRendersAsInlineCase() {
        let inlines = MarkdownInlineParser(references: [:]).parse("a[^1]")
        #expect(inlines.contains {
            if case .footnoteReference(let label) = $0 { return label == "1" }
            return false
        })
        #expect(inlines.plainText == "a")
    }

    // MARK: - Embeds

    @Test func parsesEmbedWithLabelAndDimensions() {
        let inlines = MarkdownInlineParser(references: [:]).parse("![[photo.png|320x200]]")
        guard case .embed(let target, let label)? = inlines.first else {
            Issue.record("expected an embed, got \(inlines)")
            return
        }
        #expect(target == "photo.png")
        #expect(label == "photo.png")
    }

    @Test func parsesEmbedWithAlias() {
        let inlines = MarkdownInlineParser(references: [:]).parse("![[Design notes|the brief]]")
        guard case .embed(let target, let label)? = inlines.first else {
            Issue.record("expected an embed, got \(inlines)")
            return
        }
        #expect(target == "Design notes")
        #expect(label == "the brief")
    }

    @Test func parsesEmbedTargetWithHeading() {
        let request = TransclusionRequest.parse("Design notes#Risks")
        #expect(request.target == "Design notes")
        #expect(request.heading == "Risks")
        #expect(request.blockID == nil)
        #expect(!request.isWholeNote)
    }

    @Test func parsesBlockReference() {
        let request = TransclusionRequest.parse("Design notes#^abc123")
        #expect(request.blockID == "abc123")
        #expect(request.heading == nil)
    }

    @Test func plainEmbedRequestHasNoFragment() {
        #expect(TransclusionRequest.parse("Note").isWholeNote)
    }

    // MARK: - Slicing

    @Test func sectionSlicingStopsAtSameLevelHeading() {
        let markdown = """
        # Title

        Intro.

        ## Risks

        One risk.

        ### Detail

        More.

        ## Next

        Other.
        """
        let section = TransclusionSlicer.section(from: markdown, heading: "Risks")
        #expect(section?.contains("One risk.") == true)
        #expect(section?.contains("More.") == true)
        #expect(section?.contains("Other.") == false)
    }

    @Test func sectionSlicingIsCaseInsensitive() {
        let markdown = """
        ## Risks
        Text.
        """
        #expect(TransclusionSlicer.section(from: markdown, heading: "risks")?.contains("Text.") == true)
    }

    @Test func missingSectionReturnsNil() {
        #expect(TransclusionSlicer.section(from: "## A\nx", heading: "B") == nil)
    }

    @Test func blockSlicingDropsTheMarker() {
        let markdown = """
        First paragraph.

        The quoted block. ^abc

        Last paragraph.
        """
        let block = TransclusionSlicer.block(from: markdown, id: "abc")
        #expect(block == "The quoted block.")
    }

    // MARK: - Vault resolution and unlinked mentions

    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(
                to: root.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        return root
    }

    @Test func resolvesNoteByTitleAndPath() throws {
        let root = try makeVault(["Design notes.md": "# Design notes\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VaultScanner.markdownFiles(in: root)

        #expect(VaultScanner.resolve("Design notes", in: files)?.title == "Design notes")
        #expect(VaultScanner.resolve("design notes.md", in: files)?.title == "Design notes")
        #expect(VaultScanner.resolve("Missing", in: files) == nil)
    }

    @Test func findsUnlinkedMentionsOnWordBoundaries() throws {
        let root = try makeVault([
            "Design notes.md": "# Design notes\n",
            "Journal.md": """
            Talked about Design notes today.
            Mentioned Design notesmith, which is a different thing.
            """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VaultScanner.markdownFiles(in: root)
        guard let target = VaultScanner.resolve("Design notes", in: files) else {
            Issue.record("target note not found")
            return
        }

        let mentions = VaultScanner.unlinkedMentions(of: target.url, in: files)
        #expect(mentions.count == 1)
        #expect(mentions.first?.line == 1)
    }

    @Test func skipsLinesThatAlreadyLink() throws {
        let root = try makeVault([
            "Design notes.md": "# Design notes\n",
            "Journal.md": "Already linked [[Design notes]].\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VaultScanner.markdownFiles(in: root)
        guard let target = VaultScanner.resolve("Design notes", in: files) else {
            Issue.record("target note not found")
            return
        }
        #expect(VaultScanner.unlinkedMentions(of: target.url, in: files).isEmpty)
    }

    @Test func skipsMentionsInsideCodeFences() throws {
        let root = try makeVault([
            "Design notes.md": "# Design notes\n",
            "Journal.md": """
            ```
            Design notes
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VaultScanner.markdownFiles(in: root)
        guard let target = VaultScanner.resolve("Design notes", in: files) else {
            Issue.record("target note not found")
            return
        }
        #expect(VaultScanner.unlinkedMentions(of: target.url, in: files).isEmpty)
    }

    // MARK: - HTML export

    @Test func exportRendersFootnoteSection() {
        let html = MarkdownHTMLExport.body(
            from: """
            Text.[^1]

            [^1]: The note.
            """
        )
        #expect(html.contains("footnote-ref"))
        #expect(html.contains("<section class=\"footnotes\">"))
        #expect(html.contains("The note."))
    }

    @Test func exportDegradesEmbedsToLinks() {
        let html = MarkdownHTMLExport.body(from: "![[Design notes|the brief]]")
        #expect(html.contains("class=\"embed\""))
        #expect(html.contains("the brief"))
    }
}
