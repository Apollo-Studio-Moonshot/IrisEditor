import Foundation

/// Unsaved editor text kept around so a crash or accidental close does not lose work.
struct Draft: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var updatedAt: Date
    var restoredFromFile: String?
}

/// Stores one JSON file per draft at Application Support/IrisEditor/Drafts/<uuid>.json.
enum DraftStore {
    private static var draftsURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IrisEditor", isDirectory: true)
            .appendingPathComponent("Drafts", isDirectory: true)
    }

    private static func fileURL(for id: UUID) -> URL {
        draftsURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
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

    /// All readable drafts, newest first. Corrupt files are skipped.
    static func loadAll() -> [Draft] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: draftsURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let decoder = makeDecoder()
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> Draft? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Draft.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ draft: Draft) {
        guard let data = try? makeEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: draft.id), options: [.atomic])
    }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// Removes drafts that have not been touched within `days`.
    static func prune(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        for draft in loadAll() where draft.updatedAt < cutoff {
            delete(id: draft.id)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: draftsURL)
    }
}
