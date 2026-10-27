import AppKit

/// Converts the rendered preview HTML into RTF so documents can be shared with
/// rich-text apps that do not understand Markdown.
@MainActor
enum MarkdownRTFExporter {
    static func data(html: String) -> Data? {
        guard let htmlData = html.data(using: .utf8) else { return nil }
        guard let attributed = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return nil
        }

        let range = NSRange(location: 0, length: attributed.length)
        return try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
