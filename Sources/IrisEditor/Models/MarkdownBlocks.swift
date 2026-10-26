import Foundation

/// A parsed Markdown block, sufficient for the preview renderer.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case blockQuote(lines: [String])
    case codeBlock(language: String?, lines: [String])
    case unorderedList(items: [String])
    case orderedList(items: [MarkdownOrderedItem])
    case thematicBreak
}

struct MarkdownOrderedItem: Equatable {
    let number: Int
    let text: String
}

/// A lightweight line-based Markdown block parser used by the preview.
///
/// It intentionally covers the common subset (headings, lists, quotes, fenced code,
/// rules, paragraphs) and leaves inline styling to `AttributedString(markdown:)`.
enum MarkdownBlockParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n").map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var unordered: [String] = []
        var ordered: [MarkdownOrderedItem] = []
        var openFence: String?
        var fenceLanguage: String?
        var codeLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        func flushQuote() {
            if !quote.isEmpty {
                blocks.append(.blockQuote(lines: quote))
                quote = []
            }
        }

        func flushLists() {
            if !unordered.isEmpty {
                blocks.append(.unorderedList(items: unordered))
                unordered = []
            }
            if !ordered.isEmpty {
                blocks.append(.orderedList(items: ordered))
                ordered = []
            }
        }

        func flushAll() {
            flushParagraph()
            flushQuote()
            flushLists()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Inside a fenced code block: keep lines verbatim until the closing fence.
            if let fence = openFence {
                if closingFence(trimmed, marker: fence) {
                    blocks.append(.codeBlock(language: fenceLanguage, lines: codeLines))
                    openFence = nil
                    fenceLanguage = nil
                    codeLines = []
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if let (marker, language) = openingFence(trimmed) {
                flushAll()
                openFence = marker
                fenceLanguage = language
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if isHorizontalRule(trimmed) {
                flushAll()
                blocks.append(.thematicBreak)
                continue
            }

            if let (level, headingText) = heading(in: trimmed) {
                flushAll()
                blocks.append(.heading(level: level, text: headingText))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushLists()
                var content = String(trimmed.dropFirst())
                if content.first == " " { content.removeFirst() }
                quote.append(content)
                continue
            }

            if trimmed.count >= 2, "-*+".contains(trimmed.first!), trimmed.dropFirst().first == " " {
                flushParagraph()
                flushQuote()
                if !ordered.isEmpty {
                    blocks.append(.orderedList(items: ordered))
                    ordered = []
                }
                unordered.append(String(trimmed.dropFirst(2)))
                continue
            }

            if let item = orderedItem(in: trimmed) {
                flushParagraph()
                flushQuote()
                if !unordered.isEmpty {
                    blocks.append(.unorderedList(items: unordered))
                    unordered = []
                }
                ordered.append(item)
                continue
            }

            flushQuote()
            flushLists()
            paragraph.append(trimmed)
        }

        // An unclosed fence still renders as a code block (matches common editors).
        if openFence != nil {
            blocks.append(.codeBlock(language: fenceLanguage, lines: codeLines))
        }
        flushAll()
        return blocks
    }

    // MARK: - Line classifiers

    private static func openingFence(_ trimmed: String) -> (marker: String, language: String?)? {
        let marker: String
        if trimmed.hasPrefix("```") { marker = "```" }
        else if trimmed.hasPrefix("~~~") { marker = "~~~" }
        else { return nil }
        let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let language = info.split(separator: " ").first.map(String.init)
        return (marker, language)
    }

    private static func closingFence(_ trimmed: String, marker: String) -> Bool {
        !trimmed.isEmpty
            && trimmed.replacingOccurrences(of: " ", with: "") == marker
            && trimmed.hasPrefix(marker)
    }

    private static func heading(in trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        for character in trimmed {
            if character == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        if rest.isEmpty { return (level, "") }
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func orderedItem(in trimmed: String) -> MarkdownOrderedItem? {
        var digits = ""
        for character in trimmed {
            if character.isNumber { digits.append(character) } else { break }
        }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
        let remainder = afterDigits.dropFirst()
        guard remainder.isEmpty || remainder.first == " " || remainder.first == "\t" else { return nil }
        return MarkdownOrderedItem(number: number, text: remainder.trimmingCharacters(in: .whitespaces))
    }
}
