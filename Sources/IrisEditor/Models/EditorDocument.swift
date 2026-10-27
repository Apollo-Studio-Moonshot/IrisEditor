import Foundation

@MainActor
final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()

    @Published var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            recomputeStatistics()
        }
    }

    @Published var fileURL: URL?
    @Published var isDirty: Bool = false

    private var cachedLineIndex: TextLineIndex?
    private var visibleWordCount = 0
    private var visibleCharacterCount = 0

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled.md"
    }

    var lineCount: Int {
        cachedLineIndex?.lineCount ?? 1
    }

    /// Word count with Markdown syntax markers stripped, so text like `**bold**` or
    /// `# Heading` counts only the visible words rather than the formatting characters.
    var wordCount: Int {
        visibleWordCount
    }

    var characterCount: Int {
        visibleCharacterCount
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

    /// Statistics are computed once per edit instead of once per status-bar read; the
    /// status bar asks for line, word, and character counts on every body evaluation.
    private func recomputeStatistics() {
        let visible = MarkdownPlainText.stripped(text)
        visibleWordCount = visible.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        visibleCharacterCount = visible.count
        cachedLineIndex = TextLineIndex(text)
    }
}
