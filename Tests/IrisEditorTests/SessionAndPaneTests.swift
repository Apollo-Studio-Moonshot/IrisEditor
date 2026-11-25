import Foundation
import Testing
@testable import IrisEditor

@Suite("Session restore and side pane")
struct SessionAndPaneTests {

    @Test func fileIndexSkipsUntitledTabs() {
        let paths: [String?] = ["/a.md", nil, "/b.md", "/c.md"]
        #expect(SessionTabRestore.fileIndex(tabFilePaths: paths, activeTabIndex: 2) == 1)
        #expect(SessionTabRestore.fileIndex(tabFilePaths: paths, activeTabIndex: 3) == 2)
        #expect(SessionTabRestore.fileIndex(tabFilePaths: paths, activeTabIndex: 1) == -1)
        #expect(SessionTabRestore.fileIndex(tabFilePaths: paths, activeTabIndex: 0) == 0)
    }

    @Test func restoredSelectionKeepsTheActiveFile() {
        let index = SessionTabRestore.restoredSelection(
            restoredFileCount: 3,
            recoveredDraftIDs: [UUID()],
            activeFileIndex: 1,
            activeDraftID: nil
        )
        #expect(index == 1)
    }

    @Test func restoredSelectionFocusesTheActiveDraft() {
        let draft = UUID()
        let other = UUID()
        let index = SessionTabRestore.restoredSelection(
            restoredFileCount: 1,
            recoveredDraftIDs: [other, draft],
            activeFileIndex: -1,
            activeDraftID: draft
        )
        #expect(index == 2)
    }

    @Test func restoredSelectionFallsBackToTheFirstDraft() {
        let index = SessionTabRestore.restoredSelection(
            restoredFileCount: 2,
            recoveredDraftIDs: [UUID()],
            activeFileIndex: -1,
            activeDraftID: nil
        )
        #expect(index == 2)
    }

    @Test func sessionDecodesWithoutActiveDraftID() throws {
        let json = """
        {"openFiles":["/a.md"],"activeIndex":0,"viewMode":"split","sidebarVisible":true,"sidebarPane":"files"}
        """
        let session = try JSONDecoder().decode(EditorSession.self, from: Data(json.utf8))
        #expect(session.activeDraftID == nil)
        #expect(session.openFiles == ["/a.md"])
        #expect(session.activeIndex == 0)
    }

    @Test func sidePanePrefersADirtyOpenBuffer() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let seed = SidePaneContents.load(
            targetURL: url,
            openDocuments: [
                SidePaneContents.OpenBuffer(url: url, text: "unsaved", isDirty: true)
            ],
            fallbackText: "fallback",
            read: { _ in "from disk" }
        )
        #expect(seed.text == "unsaved")
        #expect(seed.isDirty)
        #expect(seed.fileURL?.path == url.path)
    }

    @Test func sidePaneReadsDiskWhenTheFileIsNotOpen() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let seed = SidePaneContents.load(
            targetURL: url,
            openDocuments: [],
            fallbackText: "fallback",
            read: { _ in "from disk" }
        )
        #expect(seed.text == "from disk")
        #expect(seed.isDirty == false)
        #expect(seed.fileURL?.path == url.path)
    }

    @Test func sidePaneCopiesTheFallbackWhenThereIsNoFile() {
        let seed = SidePaneContents.load(
            targetURL: nil,
            openDocuments: [],
            fallbackText: "draft",
            read: { _ in "from disk" }
        )
        #expect(seed.text == "draft")
        #expect(seed.isDirty)
        #expect(seed.fileURL == nil)
    }
}
