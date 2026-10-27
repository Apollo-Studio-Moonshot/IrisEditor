import Foundation

/// The window and workspace configuration Iris restores when it relaunches.
struct EditorSession: Codable, Equatable, Sendable {
    var openFiles: [String] = []
    var activeIndex: Int = 0
    var viewMode: String = "split"
    var sidebarVisible: Bool = true
    var sidebarPane: String = "files"
    var vaultRoot: String?
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
