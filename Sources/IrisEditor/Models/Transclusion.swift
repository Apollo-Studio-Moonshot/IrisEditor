import Foundation

/// Parsed form of an Obsidian transclusion target.
///
/// `![[Note]]` embeds a whole note, `![[Note#Heading]]` embeds one section,
/// `![[Note#^block]]` embeds a single block, and `![[image.png]]` embeds an attachment.
struct TransclusionRequest: Equatable {
    /// The note name or path exactly as written, without the `#fragment`.
    let target: String
    /// Heading text after `#`, when the embed addresses a section.
    let heading: String?
    /// Block id after `#^`, when the embed addresses a single block.
    let blockID: String?

    /// The three forms are mutually exclusive in Obsidian, so a plain embed has both
    /// fragments nil and resolves to the whole file.
    var isWholeNote: Bool { heading == nil && blockID == nil }

    static func parse(_ raw: String) -> TransclusionRequest {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.firstIndex(of: "#") else {
            return TransclusionRequest(target: trimmed, heading: nil, blockID: nil)
        }

        let target = String(trimmed[trimmed.startIndex..<hashIndex])
            .trimmingCharacters(in: .whitespaces)
        var fragment = String(trimmed[trimmed.index(after: hashIndex)...])
            .trimmingCharacters(in: .whitespaces)

        if fragment.hasPrefix("^") {
            fragment.removeFirst()
            return TransclusionRequest(
                target: target,
                heading: nil,
                blockID: fragment.trimmingCharacters(in: .whitespaces)
            )
        }
        return TransclusionRequest(
            target: target,
            heading: fragment.isEmpty ? nil : fragment,
            blockID: nil
        )
    }
}

/// What an embed resolved to, ready for the preview to render.
enum TransclusionContent: Equatable {
    /// A note, or a slice of one, with its own link definitions so nested wikilinks
    /// and reference-style links resolve inside the embedded body.
    case markdown(title: String, text: String, url: URL?)
    /// An attachment the preview can show inline (image files only for now).
    case image(URL)
    /// The target could not be resolved; the preview shows a quiet placeholder.
    case unresolved(reason: String)
}

/// Picks the part of a note an embed asked for.
enum TransclusionSlicer {

    /// Returns the section under `heading` (heading line included), or nil when absent.
    static func section(from markdown: String, heading: String) -> String? {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var start: Int?
        var level: Int?

        for (index, line) in lines.enumerated() {
            guard let found = headingLevel(of: line) else { continue }
            if start == nil {
                guard normalized(line.dropFirst(found + 1)) == normalized(Substring(heading)) else {
                    continue
                }
                start = index
                level = found
            } else if let level, found <= level {
                return lines[start!..<index].joined(separator: "\n")
            }
        }

        guard let start, let level else { return nil }
        _ = level
        return lines[start...].joined(separator: "\n")
    }

    /// Returns the single block marked with `^id` (the paragraph that ends with it).
    static func block(from markdown: String, id: String) -> String? {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let marker = "^\(id)"

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(marker) else { continue }

            // Walk back to the start of the paragraph and forward to its end.
            var first = index
            while first > 0, !lines[first - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                first -= 1
            }
            var last = index
            while last + 1 < lines.count,
                  !lines[last + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                last += 1
            }
            return lines[first...last]
                .joined(separator: "\n")
                .replacingOccurrences(of: marker, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func headingLevel(of line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let level = trimmed.prefix { $0 == "#" }.count
        guard level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return level
    }

    private static func normalized<S: StringProtocol>(_ text: S) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
}
