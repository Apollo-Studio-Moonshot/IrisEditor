import Foundation

/// Chooses the text a second editor pane should show.
enum SidePaneContents {
    struct OpenBuffer: Equatable {
        var url: URL?
        var text: String
        var isDirty: Bool
    }

    struct Seed: Equatable {
        var text: String
        var fileURL: URL?
        var isDirty: Bool
    }

    /// Prefers an already-open buffer for `targetURL`, then the file on disk, then `fallbackText`.
    static func load(
        targetURL: URL?,
        openDocuments: [OpenBuffer],
        fallbackText: String,
        read: (URL) -> String?
    ) -> Seed {
        if let targetURL {
            let targetPath = targetURL.standardizedFileURL.path
            if let open = openDocuments.first(where: { $0.url?.standardizedFileURL.path == targetPath }) {
                return Seed(text: open.text, fileURL: open.url, isDirty: open.isDirty)
            }
            if let contents = read(targetURL) {
                return Seed(text: contents, fileURL: targetURL, isDirty: false)
            }
        }
        return Seed(text: fallbackText, fileURL: nil, isDirty: true)
    }
}
