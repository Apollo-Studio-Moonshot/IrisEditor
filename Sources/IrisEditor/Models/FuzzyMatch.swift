import Foundation

/// Lightweight fuzzy matching for the quick switcher and command palette.
///
/// A candidate matches when every character of the query appears in order. The score
/// rewards consecutive runs, word boundaries, and prefix matches so that typing `mdt`
/// ranks `Markdown Test` above an incidental subsequence match.
enum FuzzyMatch {
    /// Returns a score when `candidate` is a subsequence of `query`, otherwise `nil`.
    static func score(query: String, candidate: String) -> Double? {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }

        let haystack = Array(candidate.lowercased())
        guard haystack.count >= needle.count else { return nil }

        var needleIndex = 0
        var score = 0.0
        var previousMatch = -2

        for (index, character) in haystack.enumerated() {
            guard needleIndex < needle.count else { break }
            guard character == needle[needleIndex] else { continue }

            score += 1
            if index == previousMatch + 1 {
                score += 3
            }
            if isBoundary(at: index, in: haystack) {
                score += 4
            }
            previousMatch = index
            needleIndex += 1
        }

        guard needleIndex == needle.count else { return nil }

        score -= Double(haystack.count) * 0.05

        let loweredQuery = query.lowercased()
        let loweredCandidate = candidate.lowercased()
        if loweredCandidate == loweredQuery {
            score += 20
        } else if loweredCandidate.hasPrefix(loweredQuery) {
            score += 10
        } else if loweredCandidate.split(separator: " ").contains(where: { $0.hasPrefix(loweredQuery) }) {
            score += 6
        }

        return score
    }

    static func matches(query: String, candidate: String) -> Bool {
        score(query: query, candidate: candidate) != nil
    }

    private static func isBoundary(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return previous == " " || previous == "-" || previous == "_" || previous == "/" || previous == "."
    }
}
