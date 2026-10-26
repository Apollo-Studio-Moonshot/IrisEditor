import Foundation

/// Plain-text search with optional case-sensitivity and whole-word matching,
/// shared by the editor and tests.
enum TextSearch {
    static func nsRanges(
        of query: String,
        in text: String,
        caseSensitive: Bool = false,
        wholeWord: Bool = false
    ) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let text = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

        while searchRange.length > 0 {
            let found = text.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }

            if !wholeWord || isWholeWordMatch(found, in: text) {
                ranges.append(found)
            }

            let nextLocation = NSMaxRange(found)
            guard nextLocation < text.length else { break }
            searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
        }

        return ranges
    }

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        nsRanges(of: query, in: text).compactMap { Range($0, in: text) }
    }

    /// A match is a whole word when neither edge touches a letter, digit, or underscore.
    /// Composed-character ranges keep Unicode letters (for example “é” or “日本”) intact.
    private static func isWholeWordMatch(_ match: NSRange, in text: NSString) -> Bool {
        !isWordCharacter(at: match.location - 1, in: text)
            && !isWordCharacter(at: NSMaxRange(match), in: text)
    }

    private static func isWordCharacter(at index: Int, in text: NSString) -> Bool {
        guard index >= 0, index < text.length else { return false }
        let range = text.rangeOfComposedCharacterSequence(at: index)
        let content = text.substring(with: range)
        return content.unicodeScalars.contains { scalar in
            scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
        }
    }
}

/// Cached mapping between UTF-16 offsets and logical line numbers.
///
/// Wrapped lines are layout-only; this index only counts hard line breaks, which is
/// exactly what the line-number gutter and go-to-line command need.
struct TextLineIndex {
    private let starts: [Int]
    private let textLength: Int

    init(_ text: String) {
        let string = text as NSString
        textLength = string.length

        var lineStarts = [0]
        lineStarts.reserveCapacity(max(1, string.length / 40))

        var index = 0
        while index < string.length {
            let character = string.character(at: index)
            if character == 10 { // LF
                lineStarts.append(index + 1)
            } else if character == 13 { // CR or CRLF
                if index + 1 < string.length, string.character(at: index + 1) == 10 {
                    index += 1
                }
                lineStarts.append(index + 1)
            }
            index += 1
        }

        starts = lineStarts
    }

    var lineCount: Int {
        starts.count
    }

    func lineNumber(atUTF16Index index: Int) -> Int {
        guard !starts.isEmpty else { return 1 }
        let clamped = min(max(index, 0), textLength)

        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= clamped {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    func lineStart(forLine line: Int) -> Int? {
        guard line > 0, line <= starts.count else { return nil }
        return starts[line - 1]
    }
}
