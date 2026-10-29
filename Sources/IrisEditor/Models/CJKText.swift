import Foundation

/// Unicode helpers for Chinese, Japanese, and Korean text.
///
/// CJK scripts do not separate words with spaces, so the editor treats each
/// ideograph and kana syllable as its own word when counting and when moving
/// word-wise. Latin, Cyrillic, Hangul, and other space-separated scripts keep
/// their usual whitespace-delimited behavior.
enum CJKText {
    /// Script ranges whose characters each count as a separate word.
    ///
    /// Hangul is intentionally excluded: Korean is written with spaces between
    /// words, so counting each syllable would inflate word counts ~3×.
    private static let wordRanges: [ClosedRange<UInt32>] = [
        0x2E80...0x2EFF,   // CJK Radicals Supplement
        0x2F00...0x2FDF,   // Kangxi Radicals
        0x3040...0x309F,   // Hiragana
        0x30A0...0x30FF,   // Katakana
        0x3100...0x312F,   // Bopomofo
        0x31A0...0x31BF,   // Bopomofo Extended
        0x31F0...0x31FF,   // Katakana Phonetic Extensions
        0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
        0x4E00...0x9FFF,   // CJK Unified Ideographs
        0xF900...0xFAFF,   // CJK Compatibility Ideographs
        0xFF65...0xFF9F,   // Halfwidth Katakana
        0x20000...0x2EBEF, // CJK Unified Ideographs Extensions B–F
        0x2F800...0x2FA1F, // CJK Compatibility Ideographs Supplement
        0x30000...0x3134F, // CJK Unified Ideographs Extensions G–H
    ]

    /// True when `scalar` belongs to a script that writes words without spaces.
    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        wordRanges.contains { $0.contains(scalar.value) }
    }

    /// True when any scalar in `character` is a CJK ideograph or kana syllable.
    ///
    /// Checking every scalar keeps decomposed kana (base + combining dakuten) and
    /// ideographs followed by variation selectors recognized as one CJK character.
    static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { isWordScalar($0) }
    }

    /// Number of words in `text`, counting each CJK character individually.
    ///
    /// A whitespace-separated token contributes one word for each CJK character
    /// plus one for any non-CJK word content it also contains. Punctuation and
    /// other symbols next to CJK text are not counted, and tokens with no CJK
    /// characters keep the editor's existing one-word-per-token behavior.
    static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .reduce(0) { $0 + words(inToken: $1) }
    }

    private static func words(inToken token: Substring) -> Int {
        var cjkCount = 0
        var hasOtherWordContent = false

        for character in token {
            if isWordCharacter(character) {
                cjkCount += 1
            } else if character.isLetter || character.isNumber {
                hasOtherWordContent = true
            }
        }

        guard cjkCount > 0 else { return 1 }
        return cjkCount + (hasOtherWordContent ? 1 : 0)
    }
}
