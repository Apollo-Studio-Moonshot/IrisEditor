import Foundation
import Testing
@testable import IrisEditor

struct FuzzyMatchTests {
    @Test func matchesSubsequences() {
        #expect(FuzzyMatch.matches(query: "mdt", candidate: "Markdown Test"))
        #expect(FuzzyMatch.matches(query: "otl", candidate: "Outline"))
        #expect(!FuzzyMatch.matches(query: "zzz", candidate: "Markdown Test"))
    }

    @Test func exactAndPrefixMatchesOutrankScatteredMatches() {
        let exact = FuzzyMatch.score(query: "outline", candidate: "Outline") ?? 0
        let prefix = FuzzyMatch.score(query: "out", candidate: "Outline") ?? 0
        let scattered = FuzzyMatch.score(query: "otl", candidate: "Outline") ?? 0

        #expect(exact > prefix)
        #expect(prefix > scattered)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatch.score(query: "", candidate: "anything") == 0)
    }

    @Test func scoreIsCaseInsensitive() {
        #expect(FuzzyMatch.matches(query: "README", candidate: "readme.md"))
    }
}

struct UnicodeTextSearchTests {
    @Test func wholeWordMatchesAccentedAndCJKLetters() {
        let text = "café cafeteria 日本 日本人"
        #expect(TextSearch.nsRanges(of: "café", in: text, wholeWord: true).count == 1)
        #expect(TextSearch.nsRanges(of: "日本", in: text, wholeWord: true).count == 1)
    }

    @Test func emojiEdgesAreNotWordCharacters() {
        #expect(TextSearch.nsRanges(of: "cat", in: "😺cat😺", wholeWord: true).count == 1)
    }
}

struct MarkdownOutlineTests {
    @Test func parsesATXHeadingsWithLineNumbers() {
        let headings = MarkdownOutline.headings(in: "# One\ntext\n## Two\n### Three")
        #expect(headings.map(\.level) == [1, 2, 3])
        #expect(headings.map(\.line) == [1, 3, 4])
        #expect(headings.map(\.title) == ["One", "Two", "Three"])
    }

    @Test func parsesSetextHeadings() {
        let headings = MarkdownOutline.headings(in: "Title\n=====\n\nSubtitle\n--------")
        #expect(headings.map(\.level) == [1, 2])
        #expect(headings.map(\.title) == ["Title", "Subtitle"])
        #expect(headings.map(\.line) == [1, 4])
    }

    @Test func ignoresHeadingsInsideFences() {
        let text = "# Real\n```md\n# Not a heading\n```\n## Also Real"
        let headings = MarkdownOutline.headings(in: text)
        #expect(headings.map(\.title) == ["Real", "Also Real"])
    }

    @Test func stripsClosingHashesAndInlineMarkup() {
        let headings = MarkdownOutline.headings(in: "## **Bold** and `code` ##")
        #expect(headings.count == 1)
        #expect(headings.first?.title == "Bold and code")
    }

    @Test func rejectsHashesWithoutFollowingSpace() {
        #expect(MarkdownOutline.headings(in: "#hashtag").isEmpty)
        #expect(MarkdownOutline.headings(in: "####### seven").isEmpty)
    }

    @Test func handlesCRLFLineEndings() {
        let headings = MarkdownOutline.headings(in: "# One\r\n\r\n## Two\r\n")
        #expect(headings.map(\.line) == [1, 3])
    }

    @Test func thematicBreaksAreNotSetextHeadings() {
        #expect(MarkdownOutline.headings(in: "---\n---").isEmpty)
        #expect(MarkdownOutline.headings(in: "- item\n---").isEmpty)
    }
}

struct WikiLinkTests {
    @Test func parsesWikiLinksAndAliases() {
        let inlines = MarkdownInlineParser().parse("See [[Note]] and [[Other|Alias]]")
        #expect(inlines.contains(.wikiLink(target: "Note", label: "Note")))
        #expect(inlines.contains(.wikiLink(target: "Other", label: "Alias")))
        #expect(inlines.plainText == "See Note and Alias")
    }

    @Test func emptyOrMultilineWikiLinksStayLiteral() {
        let inlines = MarkdownInlineParser().parse("[[ ]] and [[one\ntwo]]")
        #expect(!inlines.contains { inline in
            if case .wikiLink = inline { return true }
            return false
        })
    }

    @Test func highlighterMarksWikiLinks() {
        let highlights = MarkdownHighlighter.highlights(in: "See [[Note|Alias]]")
        #expect(highlights.contains { $0.token == .wikiLink })
    }

    @Test func statisticsIgnoreWikiBrackets() {
        #expect(MarkdownPlainText.words(in: "[[Note]]") == 1)
        #expect(MarkdownPlainText.stripped("[[Note|Alias]]") == "Alias")
    }
}

@MainActor
struct RecentFilesTests {
    @Test func recordingMovesFileToFrontAndDeduplicates() {
        let first = URL(fileURLWithPath: "/tmp/first.md")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        var recent = RecentFiles.recording(first, in: [])
        recent = RecentFiles.recording(second, in: recent)
        recent = RecentFiles.recording(first, in: recent)

        #expect(recent.map(\.lastPathComponent) == ["first.md", "second.md"])
    }

    @Test func recordingCapsHistoryLength() {
        var recent: [URL] = []
        for index in 0..<(RecentFiles.limit + 5) {
            recent = RecentFiles.recording(URL(fileURLWithPath: "/tmp/note-\(index).md"), in: recent)
        }
        #expect(recent.count == RecentFiles.limit)
        #expect(recent.first?.lastPathComponent == "note-\(RecentFiles.limit + 4).md")
    }
}
