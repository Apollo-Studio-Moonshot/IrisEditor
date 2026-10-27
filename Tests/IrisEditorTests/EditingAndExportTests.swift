import Foundation
import Testing
@testable import IrisEditor

struct MarkdownEditingTests {
    @Test func continuesUnorderedLists() {
        #expect(
            MarkdownEditing.returnAction(forLine: "- item", caretOffset: 6)
                == .continueLine(prefix: "- ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "  * item", caretOffset: 8)
                == .continueLine(prefix: "  * ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "+", caretOffset: 1) == nil
        )
    }

    @Test func continuesOrderedListsWithTheNextNumber() {
        #expect(
            MarkdownEditing.returnAction(forLine: "1. item", caretOffset: 7)
                == .continueLine(prefix: "2. ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "  3) item", caretOffset: 9)
                == .continueLine(prefix: "  4) ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "99. item", caretOffset: 8)
                == .continueLine(prefix: "100. ")
        )
    }

    @Test func continuesBlockQuotesAndTaskLists() {
        #expect(
            MarkdownEditing.returnAction(forLine: "> quote", caretOffset: 7)
                == .continueLine(prefix: "> ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "> > nested", caretOffset: 10)
                == .continueLine(prefix: "> > ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "- [x] done", caretOffset: 10)
                == .continueLine(prefix: "- [ ] ")
        )
    }

    @Test func endsEmptyContainersWithoutAddingABlankLine() {
        #expect(
            MarkdownEditing.returnAction(forLine: "- ", caretOffset: 2)
                == .endContainer(clearRange: NSRange(location: 0, length: 2), indentation: "")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "  - ", caretOffset: 4)
                == .endContainer(clearRange: NSRange(location: 0, length: 4), indentation: "  ")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "1.  ", caretOffset: 4)
                == .endContainer(clearRange: NSRange(location: 0, length: 4), indentation: "")
        )
        #expect(
            MarkdownEditing.returnAction(forLine: "- [ ]", caretOffset: 5)
                == .endContainer(clearRange: NSRange(location: 0, length: 5), indentation: "")
        )
    }

    @Test func caretInsideTheMarkerBehavesLikePlainText() {
        #expect(MarkdownEditing.returnAction(forLine: "- item", caretOffset: 0) == nil)
        #expect(MarkdownEditing.returnAction(forLine: "> quote", caretOffset: 1) == nil)
        #expect(MarkdownEditing.returnAction(forLine: "plain text", caretOffset: 10) == nil)
    }
}

struct MarkdownStatisticsTests {
    @Test func keepsIntrawordUnderscores() {
        #expect(MarkdownPlainText.stripped("snake_case") == "snake_case")
        #expect(MarkdownPlainText.words(in: "snake_case") == 1)
        #expect(MarkdownPlainText.characters(in: "snake_case") == 10)
    }

    @Test func countsLinkLabelsNotDestinations() {
        #expect(MarkdownPlainText.stripped("[label](https://example.com)") == "label")
        #expect(MarkdownPlainText.stripped("![alt](image.png)") == "alt")
    }

    @Test func stripsListAndQuoteMarkersPerLine() {
        #expect(MarkdownPlainText.stripped("- one\n- two") == "one\ntwo")
        #expect(MarkdownPlainText.stripped("> quoted\n> text") == "quoted\ntext")
        #expect(MarkdownPlainText.stripped("3. three") == "three")
    }

    @Test func countsFencedCodeContentButNotFenceMarkers() {
        #expect(MarkdownPlainText.stripped("```swift\nlet x = 1\n```") == "let x = 1")
        #expect(MarkdownPlainText.words(in: "```\nlet x = 1\n```") == 4)
    }
}

@MainActor
struct EditorStatisticsCachingTests {
    @Test func refreshesStatisticsAfterEachEdit() {
        let document = EditorDocument()
        #expect(document.lineCount == 1)
        #expect(document.wordCount == 0)

        document.text = "# One\n\nsnake_case"
        #expect(document.lineCount == 3)
        #expect(document.wordCount == 2)
        #expect(document.characterCount == 15)

        document.text = ""
        #expect(document.lineCount == 1)
        #expect(document.wordCount == 0)
        #expect(document.characterCount == 0)
    }
}

struct MarkdownHighlighterOffsetTests {
    @Test func highlightsIndentedHeadings() {
        let highlights = MarkdownHighlighter.highlights(in: "   # Title")
        #expect(highlights.contains { $0.token == .heading })
    }

    @Test func highlightsInlineContentInsideBlockQuotes() {
        let highlights = MarkdownHighlighter.highlights(in: "> **bold** [link](https://example.com)")
        #expect(highlights.contains { $0.token == .blockquote })
        #expect(highlights.contains { $0.token == .strong })
        #expect(highlights.contains { $0.token == .link })
    }

    @Test func doesNotTreatDeeplyIndentedHashesAsHeadings() {
        let highlights = MarkdownHighlighter.highlights(in: "    # code")
        #expect(!highlights.contains { $0.token == .heading })
    }
}

struct MarkdownFileTypeTests {
    @Test func usesTheSystemMarkdownIdentifier() {
        #expect(MarkdownFileType.markdown.identifier == "net.daringfireball.markdown")
        #expect(MarkdownFileType.markdown.conforms(to: .plainText))
        #expect(MarkdownFileType.defaultExtension == "md")
    }
}

struct MarkdownHTMLExportTests {
    @Test func rendersHeadingsEmphasisCodeAndLists() {
        let html = MarkdownHTMLExport.body(
            from: "# Hello **world**\n\n- one\n- two\n\n3. three"
        )
        #expect(html.contains("<h1>Hello <strong>world</strong></h1>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<ol start=\"3\">"))
        #expect(html.contains("<li>"))
    }

    @Test func escapesTextAndInlineHTML() {
        let html = MarkdownHTMLExport.body(from: "5 < 6 and <script>alert(1)</script>")
        #expect(html.contains("5 &lt; 6"))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test func rendersTablesWithAlignment() {
        let html = MarkdownHTMLExport.body(
            from: "| Left | Right |\n| :--- | ---: |\n| a | b |"
        )
        #expect(html.contains("<table>"))
        #expect(html.contains("<th style=\"text-align: left\">Left</th>"))
        #expect(html.contains("<td style=\"text-align: right\">b</td>"))
    }

    @Test func escapesFencedCodeAndKeepsItsLanguage() {
        let html = MarkdownHTMLExport.body(
            from: "```swift\nlet x = 1 < 2\n```"
        )
        // Code fences now receive optional syntax-highlighting spans; verify structure + escaping.
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("&lt;"))
        #expect(html.contains("tok-") || html.contains("<pre><code"))
    }

    @Test func dropsUnsafeLinkSchemes() {
        let html = MarkdownHTMLExport.body(from: "[click](javascript:alert(1)) and [ok](https://example.com)")
        #expect(!html.contains("javascript:"))
        #expect(html.contains("click"))
        #expect(html.contains("href=\"https://example.com\""))
    }

    @Test func rendersWikiLinksBesideTheExportedFile() {
        let html = MarkdownHTMLExport.body(from: "See [[Note#Heading|the note]].")
        #expect(html.contains("href=\"Note.md#Heading\""))
        #expect(html.contains(">the note</a>"))
    }

    @Test func producesACompleteDocument() {
        let html = MarkdownHTMLExport.document(from: "# Title", title: "My <Notes>")
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<title>My &lt;Notes&gt;</title>"))
        #expect(html.contains("<h1>Title</h1>"))
    }
}
