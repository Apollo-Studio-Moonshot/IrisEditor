import Foundation
import Testing
@testable import IrisEditor

@Suite("Open tasks, heading marks, and extract")
struct CompositionFeaturesTests {

    private func file(_ path: String) -> VaultFile {
        VaultFile(
            url: URL(fileURLWithPath: "/vault/\(path)"),
            name: (path as NSString).lastPathComponent,
            title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
            relativePath: path,
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func tasksSkipFencesEmptyLabelsAndCheckedItems() {
        let text = """
        - [ ] Buy milk
        - [x] Walk
        - [ ]

        ```
        - [ ] Not a task
        ```

        * [ ] Starred
        """

        let tasks = VaultTaskIndex.tasks(in: text)
        #expect(tasks.map(\.text) == ["Buy milk", "Walk", "Starred"])
        #expect(tasks.map(\.checked) == [false, true, false])
        #expect(tasks.map(\.line) == [1, 2, 9])
    }

    @Test func tasksIncludeOrderedCheckboxes() {
        let text = """
        1. [ ] Buy milk
        2. [x] Walk
        3) [ ] Starred

        ```
        1. [ ] Not a task
        ```
        """
        let tasks = VaultTaskIndex.tasks(in: text)
        #expect(tasks.map(\.text) == ["Buy milk", "Walk", "Starred"])
        #expect(tasks.map(\.checked) == [false, true, false])
        #expect(tasks.map(\.line) == [1, 2, 3])
    }

    @Test func settingCheckedUpdatesAnOrderedCheckbox() {
        let updated = VaultTaskIndex.settingChecked(
            true,
            taskText: "Buy milk",
            preferredLine: 1,
            in: "1. [ ] Buy milk"
        )
        #expect(updated == "1. [x] Buy milk")
    }

    @Test func settingCheckedPrefersTheNamedLine() {
        let text = """
        - [ ] Same
        - [ ] Same
        """
        let updated = VaultTaskIndex.settingChecked(true, taskText: "Same", preferredLine: 2, in: text)
        #expect(updated == """
        - [ ] Same
        - [x] Same
        """)
    }

    @Test func settingCheckedFallsBackWhenTheLineMoved() {
        let text = """
        - [ ] Buy milk
        Something else
        """
        let updated = VaultTaskIndex.settingChecked(true, taskText: "Buy milk", preferredLine: 9, in: text)
        #expect(updated == """
        - [x] Buy milk
        Something else
        """)
    }

    @Test func settingCheckedReturnsNilWhenTheTaskIsGone() {
        let updated = VaultTaskIndex.settingChecked(true, taskText: "Missing", preferredLine: 1, in: "- [ ] Other")
        #expect(updated == nil)
    }

    @Test func derivedIndexKeepsOpenTasksAndHeadingLinks() {
        let project = file("Project.md")
        let meeting = file("Meeting.md")
        let alias = """
        ---
        aliases:
          - Plan
        ---
        # Ideas

        - [ ] Draft the outline
        - [x] Already done
        """
        let notes = """
        See [[Plan#Ideas]] and [[Project#Missing]].

        ```
        [[Plan#Ideas]]
        ```

        `[[Plan#Ideas]]`

        [[Project#^block]]
        """

        let snapshot = VaultDerivedIndex.build(entries: [
            (file: project, text: alias),
            (file: meeting, text: notes)
        ])

        #expect(snapshot.openTasks.map(\.text) == ["Draft the outline"])
        #expect(snapshot.openTasks.first?.sourceTitle == "Project")

        let marks = HeadingBacklinkIndex.marks(
            in: alias,
            documentURL: project.url,
            references: snapshot.headingReferences
        )
        #expect(marks.count == 1)
        let sources = marks[5] ?? marks.values.first ?? []
        #expect(sources.map(\.sourceTitle) == ["Meeting"])
        #expect(sources.first?.line == 1)
    }

    @Test func headingFragmentMatchesTheLeaf() {
        #expect(HeadingBacklinkIndex.matchKeys("Parent#Child") == ["parent#child", "child"])
        #expect(HeadingBacklinkIndex.matchKeys("^block").isEmpty)
        #expect(HeadingBacklinkIndex.normalize("  Ideas  ") == "ideas")
    }

    @Test func caretExpandsToTheParagraph() {
        let text = "Alpha\n\nBeta is a paragraph\nthat wraps\n\nGamma"
        let wraps = (text as NSString).range(of: "wraps")
        let range = NoteExtraction.paragraphRange(
            in: text,
            selection: NSRange(location: wraps.location, length: 0)
        )
        #expect((text as NSString).substring(with: range) == "Beta is a paragraph\nthat wraps")
    }

    @Test func explicitSelectionIsKept() {
        let text = "Alpha beta gamma"
        let beta = (text as NSString).range(of: "beta")
        let range = NoteExtraction.paragraphRange(in: text, selection: beta)
        #expect(range == beta)
    }

    @Test func caretOnTheFollowingBlankLineUsesTheParagraphAbove() {
        let text = "Alpha\n\nBeta"
        let range = NoteExtraction.paragraphRange(
            in: text,
            selection: NSRange(location: 6, length: 0)
        )
        #expect((text as NSString).substring(with: range) == "Alpha")
    }

    @Test func extractionNamesAndBodies() {
        #expect(NoteExtraction.suggestedTitle(from: "# Q3 / Plan\n\nBody") == "Q3 Plan")
        #expect(NoteExtraction.fileName(from: "A<B>") == "A B")
        #expect(NoteExtraction.embed(named: "Q3 Plan") == "![[Q3 Plan]]")
        #expect(NoteExtraction.noteBody(title: "Q3 Plan", excerpt: "Just text") == "# Q3 Plan\n\nJust text\n")
        #expect(NoteExtraction.noteBody(title: "Ignored", excerpt: "# Already\n\nBody") == "# Already\n\nBody\n")
    }

    @Test func dailyNoteCarriesTheOpenTaskLens() {
        let template = DailyNotes.defaultTemplate(date: Date(timeIntervalSince1970: 0))
        #expect(template.contains("## Today"))
        #expect(template.contains("- [ ]"))
        #expect(template.contains(VaultTaskIndex.fenceBlock))
    }
}
