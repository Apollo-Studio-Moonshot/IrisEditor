import Foundation

/// The window and workspace configuration Iris restores when it relaunches.
struct EditorSession: Codable, Equatable, Sendable {
    var openFiles: [String] = []
    /// Index into `openFiles`, or `-1` when the active tab is an untitled draft.
    var activeIndex: Int = 0
    var viewMode: String = "split"
    var sidebarVisible: Bool = true
    var sidebarPane: String = "files"
    var vaultRoot: String?
    /// Draft that was active when `activeIndex` is `-1`. Older session files omit this key.
    var activeDraftID: UUID?
}

/// Maps the live tab strip onto the file list a session stores, and back again.
enum SessionTabRestore {
    /// Index of the active tab inside the file-only list, or `-1` when that tab has no file.
    static func fileIndex(tabFilePaths: [String?], activeTabIndex: Int) -> Int {
        guard tabFilePaths.indices.contains(activeTabIndex) else { return 0 }
        guard tabFilePaths[activeTabIndex] != nil else { return -1 }
        return tabFilePaths.prefix(activeTabIndex).compactMap { $0 }.count
    }

    /// Index into restored file tabs followed by recovered drafts.
    static func restoredSelection(
        restoredFileCount: Int,
        recoveredDraftIDs: [UUID],
        activeFileIndex: Int,
        activeDraftID: UUID?
    ) -> Int {
        if activeFileIndex >= 0, restoredFileCount > 0 {
            return min(activeFileIndex, restoredFileCount - 1)
        }
        if let activeDraftID, let offset = recoveredDraftIDs.firstIndex(of: activeDraftID) {
            return restoredFileCount + offset
        }
        if activeFileIndex < 0, !recoveredDraftIDs.isEmpty {
            return restoredFileCount
        }
        return 0
    }
}

/// Reads and writes the last session at Application Support/IrisEditor/session.json.
enum SessionStore {
    private static var rootURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IrisEditor", isDirectory: true)
    }

    private static var fileURL: URL {
        rootURL.appendingPathComponent("session.json")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Returns the saved session, or `nil` when nothing valid has been stored.
    static func load() -> EditorSession? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? makeDecoder().decode(EditorSession.self, from: data)
    }

    static func save(_ session: EditorSession) {
        guard let data = try? makeEncoder().encode(session) else { return }
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
