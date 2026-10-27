import Foundation

// MARK: - CodeSyntaxHighlighter

/// A deliberately small, dependency-free syntax highlighter that produces tokens suitable
/// for both SwiftUI `AttributedString` coloring and HTML export.
///
/// The recognizer is intentionally language-agnostic: it applies a handful of regex patterns
/// ordered by reliability (strings/comments first so they swallow keywords, then numbers,
/// identifiers matched against a language keyword table, then punctuation). For unknown
/// languages every character falls into `.plain`, which is the correct graceful fallback.
enum CodeSyntaxHighlighter {

    // MARK: - Types

    enum TokenKind: Equatable {
        case keyword
        case string
        case comment
        case number
        case type
        case function
        case property
        case punctuation
        case plain
    }

    struct Token: Equatable {
        let range: NSRange
        let kind: TokenKind
    }

    // MARK: - Public API

    static func tokens(in source: String, language: String?) -> [Token] {
        let ns = source as NSString
        let keywords = keywordTable(for: language)
        var result: [Token] = []
        var cursor = 0

        // Order matters: strings/comments/numbers must be consumed before identifiers.
        let patterns: [(NSRegularExpression, TokenKind)] = [
            (try! NSRegularExpression(pattern: #"""[^"\\]*(?:\\.[^"\\]*)*""#), .string),
            (try! NSRegularExpression(pattern: #"'[^'\\]*(?:\\.[^'\\]*)*'"#), .string),
            (try! NSRegularExpression(pattern: #"//[^\n]*"#), .comment),
            (try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#), .comment),
            (try! NSRegularExpression(pattern: #"#[^\n]*"#), .comment),
            (try! NSRegularExpression(pattern: #"--[^\n]*"#), .comment),
            (try! NSRegularExpression(pattern: #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#), .number),
            (try! NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b"#), .plain),
            (try! NSRegularExpression(pattern: #"[{}()\[\].,;:!?=+\-*/%<>|&~^@#]"#), .punctuation),
        ]

        while cursor < ns.length {
            var bestLocation = NSNotFound
            var bestMatch: NSTextCheckingResult?
            var bestKind: TokenKind = .plain

            for (pattern, kind) in patterns {
                let range = NSRange(location: cursor, length: ns.length - cursor)
                if let match = pattern.firstMatch(in: source, range: range) {
                    if match.range.location < bestLocation {
                        bestLocation = match.range.location
                        bestMatch = match
                        bestKind = kind
                    }
                }
            }

            guard let match = bestMatch else {
                // No pattern matched — emit remaining text as plain.
                let rest = NSRange(location: cursor, length: ns.length - cursor)
                result.append(Token(range: rest, kind: .plain))
                break
            }

            // Gap before the match (e.g. whitespace) → plain.
            if bestLocation > cursor {
                let gap = NSRange(location: cursor, length: bestLocation - cursor)
                result.append(Token(range: gap, kind: .plain))
            }

            // If this is an identifier, refine by keyword table and case conventions.
            if bestKind == .plain {
                let word = ns.substring(with: match.range)
                if keywords.contains(word) {
                    bestKind = .keyword
                } else if word.first?.isUppercase == true {
                    bestKind = .type
                } else {
                    // Heuristic: word immediately followed by `(` → function.
                    let nextLoc = NSMaxRange(match.range)
                    if nextLoc < ns.length, ns.character(at: nextLoc) == 40 { // '('
                        bestKind = .function
                    }
                }
            }

            result.append(Token(range: match.range, kind: bestKind))
            cursor = NSMaxRange(match.range)
        }

        return result
    }

    /// Returns the same highlighting applied to HTML `<span class="tok-*">…</span>` fragments
    /// suitable for inclusion inside `<pre><code>`.
    static func htmlSpans(in source: String, language: String?) -> String {
        let ns = source as NSString
        let tokens = tokens(in: source, language: language)
        var output = ""
        var cursor = 0
        for token in tokens {
            if token.range.location > cursor {
                output += escapeHTML(ns.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
            }
            let text = ns.substring(with: token.range)
            let cssClass = cssClass(for: token.kind)
            if cssClass == "tok-plain" {
                output += escapeHTML(text)
            } else {
                output += "<span class=\"\(cssClass)\">\(escapeHTML(text))</span>"
            }
            cursor = NSMaxRange(token.range)
        }
        if cursor < ns.length {
            output += escapeHTML(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return output
    }

    // MARK: - Helpers

    private static func cssClass(for kind: TokenKind) -> String {
        switch kind {
        case .keyword: return "tok-keyword"
        case .string: return "tok-string"
        case .comment: return "tok-comment"
        case .number: return "tok-number"
        case .type: return "tok-type"
        case .function: return "tok-function"
        case .property: return "tok-property"
        case .punctuation: return "tok-punctuation"
        case .plain: return "tok-plain"
        }
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func keywordTable(for language: String?) -> Set<String> {
        let lang = (language ?? "").lowercased()
        switch lang {
        case "swift":
            return ["let","var","func","class","struct","enum","protocol","extension","if","else","for","while","do","switch","case","default","break","continue","return","import","public","private","internal","open","init","deinit","static","final","lazy","weak","strong","unowned","try","catch","throw","throws","async","await","Task","@MainActor","actor","nonisolated","associatedtype","typealias","where","in","is","as","nil","true","false","self","Self","super"]
        case "python", "py":
            return ["def","class","return","if","elif","else","for","while","break","continue","pass","import","from","as","try","except","finally","raise","with","lambda","yield","global","nonlocal","async","await","True","False","None","and","or","not","in","is","self"]
        case "javascript", "js", "typescript", "ts":
            return ["let","const","var","function","class","return","if","else","for","while","do","switch","case","break","continue","new","import","export","from","default","try","catch","finally","throw","async","await","typeof","instanceof","in","of","this","super","null","undefined","true","false"]
        case "ruby":
            return ["def","end","class","module","if","elsif","else","unless","while","until","for","do","case","when","return","yield","begin","rescue","ensure","raise","require","include","attr_accessor","attr_reader","attr_writer","true","false","nil","self"]
        case "go":
            return ["func","package","import","const","var","type","struct","interface","map","chan","go","defer","return","if","else","for","range","switch","case","default","break","continue","select","true","false","nil"]
        case "rust":
            return ["fn","let","mut","const","static","struct","enum","trait","impl","pub","use","mod","crate","super","self","Self","if","else","for","while","loop","match","return","break","continue","as","where","async","await","dyn","ref","box","true","false","None","Some"]
        case "sql":
            return ["SELECT","FROM","WHERE","AND","OR","NOT","IN","IS","NULL","TRUE","FALSE","INSERT","INTO","VALUES","UPDATE","SET","DELETE","CREATE","TABLE","DROP","ALTER","INDEX","JOIN","LEFT","RIGHT","INNER","OUTER","ON","GROUP","BY","ORDER","HAVING","LIMIT","OFFSET","DISTINCT","UNION","ALL","AS","BETWEEN","LIKE","CASE","WHEN","THEN","ELSE","END"]
        default:
            return []
        }
    }
}
