import CryptoKit
import Foundation

/// One snapshot of a document's text, captured whenever autosave records a change.
struct DocumentVersion: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let savedAt: Date
    let text: String
    let fileURL: String?
}

/// Keeps the most recent snapshots per document at
/// Application Support/IrisEditor/Versions/<sha256(key)>/history.json.
enum VersionHistoryStore {
    private static let limit = 25

    private static var rootURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IrisEditor", isDirectory: true)
            .appendingPathComponent("Versions", isDirectory: true)
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

    /// Stable history identifier: the file path, or "untitled" for unsaved text.
    static func key(forFileURL url: URL?) -> String {
        guard let url else { return "untitled" }
        return url.standardizedFileURL.path
    }

    /// Folder named after the SHA256 of the key; `key.txt` inside keeps the mapping
    /// discoverable when inspecting Application Support by hand.
    private static func folderURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(name, isDirectory: true)
    }

    private static func historyURL(for key: String) -> URL {
        folderURL(for: key).appendingPathComponent("history.json")
    }

    private static func ensureFolder(for key: String) {
        let folder = folderURL(for: key)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keyURL = folder.appendingPathComponent("key.txt")
        guard !FileManager.default.fileExists(atPath: keyURL.path) else { return }
        try? Data(key.utf8).write(to: keyURL, options: [.atomic])
    }

    /// Snapshots for `key`, newest first. Missing or corrupt history reads as empty.
    static func versions(for key: String) -> [DocumentVersion] {
        guard let data = try? Data(contentsOf: historyURL(for: key)),
              let versions = try? makeDecoder().decode([DocumentVersion].self, from: data) else {
            return []
        }
        return versions.sorted { $0.savedAt > $1.savedAt }
    }

    /// Records a snapshot unless it matches the newest one, keeping at most 25.
    static func record(text: String, fileURL: URL?, key: String? = nil) {
        let historyKey = key ?? Self.key(forFileURL: fileURL)
        var existing = versions(for: historyKey)
        guard existing.first?.text != text else { return }
        existing.insert(
            DocumentVersion(id: UUID(), savedAt: Date(), text: text, fileURL: fileURL?.path),
            at: 0
        )
        if existing.count > limit {
            existing.removeLast(existing.count - limit)
        }
        write(existing, for: historyKey)
    }

    static func clear(for key: String) {
        try? FileManager.default.removeItem(at: folderURL(for: key))
    }

    static func delete(id: UUID, for key: String) {
        var existing = versions(for: key)
        guard existing.contains(where: { $0.id == id }) else { return }
        existing.removeAll { $0.id == id }
        guard !existing.isEmpty else {
            clear(for: key)
            return
        }
        write(existing, for: key)
    }

    private static func write(_ versions: [DocumentVersion], for key: String) {
        guard let data = try? makeEncoder().encode(versions) else { return }
        ensureFolder(for: key)
        try? data.write(to: historyURL(for: key), options: [.atomic])
    }
}
