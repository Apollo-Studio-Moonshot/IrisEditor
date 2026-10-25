import Foundation

@MainActor
final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()

    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled.md"
    }

    var lineCount: Int {
        TextLineIndex(text).lineCount
    }

    /// Word count with Markdown syntax markers stripped, so text like `**bold**` or
    /// `# Heading` counts only the visible words rather than the formatting characters.
    var wordCount: Int {
        MarkdownPlainText.words(in: text)
    }

    var characterCount: Int {
        MarkdownPlainText.characters(in: text)
    }

    var utf8ByteCount: Int {
        text.utf8.count
    }

    var fileSizeDescription: String {
        Self.byteFormatter.string(fromByteCount: Int64(utf8ByteCount))
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()
}
