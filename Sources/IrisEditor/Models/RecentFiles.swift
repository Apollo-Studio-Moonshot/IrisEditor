import Foundation

/// Persists the files most recently opened or saved, powering the quick switcher.
@MainActor
enum RecentFiles {
    static let defaultsKey = "IrisEditor.RecentFiles"
    static let limit = 20

    static func load() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Returns `existing` with `url` moved to the front and duplicates removed.
    static func recording(_ url: URL, in existing: [URL]) -> [URL] {
        let standardized = url.standardizedFileURL
        var updated = existing.filter { $0.standardizedFileURL != standardized }
        updated.insert(standardized, at: 0)
        if updated.count > limit {
            updated.removeLast(updated.count - limit)
        }
        return updated
    }

    static func save(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map(\.path), forKey: defaultsKey)
    }
}
