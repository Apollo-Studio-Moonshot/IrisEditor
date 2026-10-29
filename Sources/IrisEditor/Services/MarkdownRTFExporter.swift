import AppKit

/// Converts the rendered preview HTML into RTF so documents can be shared with
/// rich-text apps that do not understand Markdown.
@MainActor
enum MarkdownRTFExporter {
    static func data(html: String) -> Data? {
        guard let htmlData = html.data(using: .utf8) else { return nil }
        guard let imported = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return nil
        }

        // A dark preview theme would import as near-white runs, and RTF has no page
        // background of its own — the export would be a blank white page. Normalise the
        // colours so the text is always legible on paper while keeping emphasis.
        let attributed = normalizedForPrint(imported)
        let range = NSRange(location: 0, length: attributed.length)
        return try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Rewrites foreground/background colours to plain black-on-clear text.
    static func normalizedForPrint(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)
        guard full.length > 0 else { return mutable }

        var foreground: [(NSRange, NSColor)] = []
        mutable.enumerateAttributes(in: full) { attributes, range, _ in
            if let color = attributes[.foregroundColor] as? NSColor,
               let ink = printableInk(for: color) {
                foreground.append((range, ink))
            }
        }
        for (range, ink) in foreground {
            mutable.addAttribute(.foregroundColor, value: ink, range: range)
        }
        for key in [NSAttributedString.Key.backgroundColor, .strokeColor, .underlineColor] {
            mutable.removeAttribute(key, range: full)
        }
        // Keep links readable as plain text rather than system blue on dark themes.
        mutable.enumerateAttribute(.link, in: full) { value, range, _ in
            guard value != nil else { return }
            mutable.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        }
        return mutable
    }

    /// Maps a theme colour to something that survives printing; `nil` leaves it alone.
    private static func printableInk(for color: NSColor) -> NSColor? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return NSColor.black }
        // Perceived luminance (Rec. 601) decides whether the ink would be invisible on
        // white paper.
        let luminance = 0.299 * rgb.redComponent
            + 0.587 * rgb.greenComponent
            + 0.114 * rgb.blueComponent
        if luminance > 0.75 { return NSColor.black }
        return rgb
    }
}
