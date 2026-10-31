import Foundation

/// A starred note in the sidebar's Starred pane.
struct VaultBookmark: Identifiable, Equatable, Codable, Sendable {
    let url: URL
    /// Vault root the bookmark was created in, so the same note in another vault
    /// does not light up the wrong star.
    let vaultRoot: URL?
    let title: String
    let added: Date

    var id: String { url.standardizedFileURL.path }

    /// Folder of the note relative to its vault root (`""` at the root).
    var folder: String {
        guard let vaultRoot else { return "" }
        return VaultScanner.relativeDirectory(of: url, in: vaultRoot)
    }

    /// True when the bookmark belongs to `root` and that note is `url`.
    func matches(_ url: URL, in root: URL?) -> Bool {
        guard self.url.standardizedFileURL == url.standardizedFileURL else { return false }
        let rootPath = root?.standardizedFileURL.path
        guard let rootPath else { return vaultRoot == nil }
        return self.vaultRoot?.standardizedFileURL.path == rootPath
    }
}

/// Persistent list of starred notes, newest first.
///
/// Storage is a JSON array in `UserDefaults` so starring survives relaunches without
/// touching the vault folder. Entries whose file has vanished are still returned
/// (the pane dims them) but can be pruned with ``prune(missingFiles:)``.
enum BookmarkStore {
    private static let defaultsKey = "IrisEditor.Bookmarks"

    static func load() -> [VaultBookmark] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([VaultBookmark].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ bookmarks: [VaultBookmark]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// Inserts a bookmark at the front, replacing an existing entry for the same note.
    static func adding(_ bookmark: VaultBookmark, to bookmarks: [VaultBookmark]) -> [VaultBookmark] {
        var updated = bookmarks.filter { $0.id != bookmark.id }
        updated.insert(bookmark, at: 0)
        return updated
    }

    static func removing(_ url: URL, from bookmarks: [VaultBookmark]) -> [VaultBookmark] {
        bookmarks.filter { $0.url.standardizedFileURL != url.standardizedFileURL }
    }

    static func contains(_ url: URL?, in root: URL?, in bookmarks: [VaultBookmark]) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.matches(url, in: root) }
    }

    /// Drops entries whose file no longer exists on disk.
    static func prune(_ bookmarks: [VaultBookmark]) -> [VaultBookmark] {
        bookmarks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}

// MARK: - File listing modes

/// Sort order for the sidebar files pane.
enum VaultFileSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case name, modified, created, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date Modified"
        case .created: "Date Created"
        case .size: "Size"
        }
    }

    var systemImage: String {
        switch self {
        case .name: "textformat.abc"
        case .modified: "clock"
        case .created: "calendar"
        case .size: "arrow.up.arrow.down.square"
        }
    }
}

/// What the sidebar files pane lists: the folded tree, recent notes, or every note flat.
enum VaultFileListing: String, CaseIterable, Identifiable, Codable, Sendable {
    case tree, recent, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tree: "Folders"
        case .recent: "Recent"
        case .all: "All Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .tree: "folder"
        case .recent: "clock.arrow.circlepath"
        case .all: "list.bullet"
        }
    }
}

/// Scope selector for the standalone graph window.
enum GraphScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case local, vault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: L10n.localGraph
        case .vault: L10n.vaultGraph
        }
    }
}
