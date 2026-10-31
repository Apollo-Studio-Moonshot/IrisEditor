import Foundation

/// A parsed inline span.
///
/// Block parsing leaves inline Markdown as raw text; the preview resolves it here so
/// emphasis, code spans, links, images, escapes, line breaks, and raw HTML all render
/// consistently instead of relying on `AttributedString(markdown:)`'s partial support.
indirect enum MarkdownInline: Equatable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    /// Obsidian-style `==highlight==`.
    case highlight([MarkdownInline])
    case code(String)
    case link(destination: String, title: String?, children: [MarkdownInline])
    case image(source: String, alt: String, title: String?)
    /// Obsidian-style `[[target]]` or `[[target|label]]` link.
    case wikiLink(target: String, label: String)
    /// `[^label]` — a footnote reference. Definitions live on `MarkdownDocument.footnotes`.
    case footnoteReference(label: String)
    /// Obsidian-style `![[target]]` transclusion of a note, heading, or attachment.
    case embed(target: String, label: String)
    case softBreak
    case hardBreak
    case html(String)
}

extension Array where Element == MarkdownInline {
    /// Visible text with inline markup removed (used for image captions and alt text).
    var plainText: String {
        map { inline -> String in
            switch inline {
            case .text(let value), .code(let value), .html(let value):
                return value
            case .emphasis(let children), .strong(let children), .strikethrough(let children),
                 .highlight(let children):
                return children.plainText
            case .link(_, _, let children):
                return children.plainText
            case .image(_, let alt, _):
                return alt
            case .wikiLink(_, let label):
                return label
            case .embed(_, let label):
                return label
            case .footnoteReference:
                return ""
            case .softBreak, .hardBreak:
                return " "
            }
        }
        .joined()
    }
}

/// Shared link-destination syntax used by inline links, images, and reference definitions.
enum MarkdownLinkSyntax {

    /// Parses `destination [title]` starting just after `(` or `[label]:`.
    ///
    /// The returned `end` points at the first character after the parsed target (normally
    /// the closing `)`) so callers can decide whether the surrounding syntax is valid.
    static func parseInlineLinkTarget(
        _ characters: [Character],
        from start: Int
    ) -> (destination: String, title: String?, end: Int)? {
        guard start < characters.count else { return nil }
        var index = start
        var destination = ""

        if characters[index] == "<" {
            index += 1
            while index < characters.count, characters[index] != ">" {
                let character = characters[index]
                if character == "\n" { return nil }
                if character == "\\", index + 1 < characters.count {
                    destination.append(characters[index + 1])
                    index += 2
                    continue
                }
                destination.append(character)
                index += 1
            }
            guard index < characters.count, characters[index] == ">" else { return nil }
            index += 1
        } else {
            var depth = 0
            while index < characters.count {
                let character = characters[index]
                if character == "\\", index + 1 < characters.count {
                    destination.append(characters[index + 1])
                    index += 2
                    continue
                }
                if character.isWhitespace { break }
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                destination.append(character)
                index += 1
            }
            guard !destination.isEmpty, depth == 0 else { return nil }
        }

        while index < characters.count,
              characters[index] == " " || characters[index] == "\t" {
            index += 1
        }

        var title: String?
        if index < characters.count,
           characters[index] == "\"" || characters[index] == "'" || characters[index] == "(" {
            let opener = characters[index]
            let closer: Character = opener == "(" ? ")" : opener
            index += 1
            var value = ""
            var closed = false
            while index < characters.count {
                let character = characters[index]
                if character == "\\", index + 1 < characters.count {
                    value.append(characters[index + 1])
                    index += 2
                    continue
                }
                if character == closer {
                    closed = true
                    index += 1
                    break
                }
                if character == "\n" { return nil }
                value.append(character)
                index += 1
            }
            guard closed else { return nil }
            title = value
            while index < characters.count,
                  characters[index] == " " || characters[index] == "\t" {
                index += 1
            }
        }

        return (destination, title, index)
    }

    /// Case-insensitive, whitespace-collapsed key for reference definitions.
    static func normalizeLabel(_ label: String) -> String {
        label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}

/// Parses the inline subset of the Markdown Guide basic syntax.
struct MarkdownInlineParser {
    let references: [String: MarkdownLinkReference]

    init(references: [String: MarkdownLinkReference] = [:]) {
        self.references = references
    }

    func parse(_ text: String) -> [MarkdownInline] {
        guard !text.isEmpty else { return [] }

        let characters = Array(text)
        var tokens: [Token] = []
        var textBuffer = ""
        var index = 0

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            tokens.append(.inline(.text(textBuffer)))
            textBuffer = ""
        }

        while index < characters.count {
            let character = characters[index]

            if character == "\\" {
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    flushText()
                    tokens.append(.inline(.hardBreak))
                    index += 2
                    continue
                }
                if index + 1 < characters.count,
                   markdownEscapableCharacters.contains(characters[index + 1]) {
                    textBuffer.append(characters[index + 1])
                    index += 2
                    continue
                }
                textBuffer.append(character)
                index += 1
                continue
            }

            if character == "`" {
                let runLength = countRun(characters, at: index, character: "`")
                if let closeIndex = findCodeClose(characters, from: index + runLength, run: runLength) {
                    flushText()
                    var content = String(characters[(index + runLength)..<closeIndex])
                        .replacingOccurrences(of: "\n", with: " ")
                    if content.count >= 2,
                       content.hasPrefix(" "),
                       content.hasSuffix(" "),
                       content.contains(where: { $0 != " " }) {
                        content.removeFirst()
                        content.removeLast()
                    }
                    tokens.append(.inline(.code(content)))
                    index = closeIndex + runLength
                } else {
                    textBuffer.append(String(repeating: "`", count: runLength))
                    index += runLength
                }
                continue
            }

            if character == "\n" {
                let trailingSpaces = textBuffer.reversed().prefix { $0 == " " }.count
                if trailingSpaces >= 2 {
                    textBuffer.removeLast(trailingSpaces)
                    flushText()
                    tokens.append(.inline(.hardBreak))
                } else {
                    if trailingSpaces == 1 { textBuffer.removeLast() }
                    flushText()
                    tokens.append(.inline(.softBreak))
                }
                index += 1
                continue
            }

            if character == "!",
               index + 2 < characters.count,
               characters[index + 1] == "[",
               characters[index + 2] == "[" {
                if let parsed = parseEmbed(characters, at: index) {
                    flushText()
                    tokens.append(.inline(parsed.inline))
                    index = parsed.nextIndex
                } else {
                    textBuffer.append(character)
                    index += 1
                }
                continue
            }

            if character == "!", index + 1 < characters.count, characters[index + 1] == "[" {
                flushText()
                if let parsed = parseLinkOrImage(characters, at: index, isImage: true) {
                    tokens.append(.inline(parsed.inline))
                    index = parsed.nextIndex
                } else {
                    textBuffer.append(character)
                    index += 1
                }
                continue
            }

            if character == "[", index + 1 < characters.count, characters[index + 1] == "[" {
                if let parsed = parseWikiLink(characters, at: index) {
                    flushText()
                    tokens.append(.inline(parsed.inline))
                    index = parsed.nextIndex
                } else {
                    textBuffer.append(character)
                    index += 1
                }
                continue
            }

            if character == "[", index + 1 < characters.count, characters[index + 1] == "^" {
                if let parsed = parseFootnoteReference(characters, at: index) {
                    flushText()
                    tokens.append(.inline(parsed.inline))
                    index = parsed.nextIndex
                    continue
                }
            }

            if character == "[" {
                flushText()
                if let parsed = parseLinkOrImage(characters, at: index, isImage: false) {
                    tokens.append(.inline(parsed.inline))
                    index = parsed.nextIndex
                } else {
                    textBuffer.append(character)
                    index += 1
                }
                continue
            }

            if character == "<" {
                flushText()
                if let parsed = parseAngleBracket(characters, at: index) {
                    if case .html(let raw) = parsed.inline,
                       let tag = formattingTag(from: raw) {
                        tokens.append(.delimiter(Delimiter(
                            kind: tag.kind,
                            count: 1,
                            canOpen: !tag.isClosing,
                            canClose: tag.isClosing,
                            originalCount: 1,
                            raw: raw
                        )))
                    } else {
                        tokens.append(.inline(parsed.inline))
                    }
                    index = parsed.nextIndex
                } else {
                    textBuffer.append(character)
                    index += 1
                }
                continue
            }

            if character == "=" {
                // `==highlight==` needs exactly two equals signs; anything else is text.
                let runLength = countRun(characters, at: index, character: "=")
                guard runLength == 2 else {
                    textBuffer.append(String(repeating: "=", count: runLength))
                    index += runLength
                    continue
                }
                flushText()
                let (canOpen, canClose) = flanking(
                    characters,
                    at: index,
                    run: 2,
                    character: "="
                )
                tokens.append(.delimiter(Delimiter(
                    kind: .highlight,
                    count: 1,
                    canOpen: canOpen,
                    canClose: canClose,
                    originalCount: 2,
                    raw: nil
                )))
                index += 2
                continue
            }

            if character == "*" || character == "_" || character == "~" {
                let runLength = countRun(characters, at: index, character: character)
                if character == "~", runLength < 2 {
                    textBuffer.append(String(repeating: "~", count: runLength))
                    index += runLength
                    continue
                }
                flushText()
                let (canOpen, canClose) = flanking(
                    characters,
                    at: index,
                    run: runLength,
                    character: character
                )
                tokens.append(.delimiter(Delimiter(
                    kind: .character(character),
                    count: runLength,
                    canOpen: canOpen,
                    canClose: canClose,
                    originalCount: runLength,
                    raw: nil
                )))
                index += runLength
                continue
            }

            textBuffer.append(character)
            index += 1
        }

        flushText()
        return resolveEmphasis(tokens)
    }

    // MARK: - Emphasis

    private enum DelimiterKind: Equatable {
        case character(Character)
        case strong
        case emphasis
        case code
        case strikethrough
        case highlight
    }

    private struct Delimiter {
        let kind: DelimiterKind
        var count: Int
        let canOpen: Bool
        let canClose: Bool
        /// Length of the original delimiter run; `count` shrinks as it is consumed,
        /// but CommonMark's "rule of 3" is defined on the original run lengths.
        let originalCount: Int
        /// Original tag text for `</em>`-style delimiters; `nil` for `*`, `_`, `~`.
        let raw: String?
    }

    private enum Token {
        case inline(MarkdownInline)
        case delimiter(Delimiter)
    }

    private func resolveEmphasis(_ input: [Token]) -> [MarkdownInline] {
        var tokens = input
        var index = 0

        while index < tokens.count {
            guard case .delimiter(let closerValue) = tokens[index],
                  closerValue.canClose else {
                index += 1
                continue
            }

            var closer = closerValue
            guard let openerIndex = findOpener(in: tokens, before: index, matching: closer),
                  case .delimiter(var opener) = tokens[openerIndex] else {
                index += 1
                continue
            }

            let useCount: Int
            switch opener.kind {
            case .character(let character) where character == "~":
                useCount = 2
            case .character:
                useCount = opener.count >= 2 && closer.count >= 2 ? 2 : 1
            default:
                useCount = 1
            }

            let innerTokens = Array(tokens[(openerIndex + 1)..<index])
            let inner = flatten(innerTokens)

            let node: MarkdownInline
            switch opener.kind {
            case .character(let character) where character == "~":
                node = .strikethrough(inner)
            case .character:
                node = useCount == 2 ? .strong(inner) : .emphasis(inner)
            case .strong:
                node = .strong(inner)
            case .emphasis:
                node = .emphasis(inner)
            case .strikethrough:
                node = .strikethrough(inner)
            case .highlight:
                node = .highlight(inner)
            case .code:
                node = .code(inner.plainText)
            }

            opener.count -= useCount
            closer.count -= useCount

            var replacement: [Token] = []
            if opener.count > 0 { replacement.append(.delimiter(opener)) }
            replacement.append(.inline(node))
            if closer.count > 0 { replacement.append(.delimiter(closer)) }

            tokens.replaceSubrange(openerIndex...index, with: replacement)

            if closer.count > 0 {
                index = openerIndex + replacement.count - 1
            } else {
                index = openerIndex + replacement.count
            }
        }

        return flatten(tokens)
    }

    private func findOpener(
        in tokens: [Token],
        before index: Int,
        matching closer: Delimiter
    ) -> Int? {
        var cursor = index - 1
        while cursor >= 0 {
            if case .delimiter(let opener) = tokens[cursor],
               opener.kind == closer.kind,
               opener.canOpen,
               opener.count > 0 {
                if case .character(let character) = closer.kind, character == "~" {
                    if opener.count >= 2, closer.count >= 2 { return cursor }
                } else if closer.kind == .highlight {
                    return cursor
                } else if violatesRuleOfThree(opener: opener, closer: closer) {
                    cursor -= 1
                    continue
                } else {
                    return cursor
                }
            }
            cursor -= 1
        }
        return nil
    }

    /// CommonMark's "rule of 3": when either delimiter can both open and close,
    /// the sum of the original run lengths must not be a multiple of 3 unless both
    /// are. Without it `**a*b**` mispairs the inner `*` with the leading `**`.
    private func violatesRuleOfThree(opener: Delimiter, closer: Delimiter) -> Bool {
        guard opener.canClose || closer.canOpen else { return false }
        let total = opener.originalCount + closer.originalCount
        guard total % 3 == 0 else { return false }
        return !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
    }

    private func flatten(_ tokens: [Token]) -> [MarkdownInline] {
        var result: [MarkdownInline] = []

        for token in tokens {
            switch token {
            case .inline(let inline):
                appendMerged(inline, to: &result)
            case .delimiter(let delimiter):
                let literal: String
                if let raw = delimiter.raw {
                    literal = raw
                } else {
                    switch delimiter.kind {
                    case .character(let character):
                        literal = String(repeating: character, count: delimiter.count)
                    case .highlight:
                        // An unmatched `==` must stay in the text, not vanish.
                        literal = String(repeating: "==", count: delimiter.count)
                    case .strikethrough:
                        literal = String(repeating: "~~", count: delimiter.count)
                    case .code:
                        literal = "`"
                    case .strong, .emphasis:
                        literal = ""
                    }
                }
                if !literal.isEmpty {
                    appendMerged(.text(literal), to: &result)
                }
            }
        }

        return result
    }

    private func appendMerged(_ inline: MarkdownInline, to result: inout [MarkdownInline]) {
        if case .text(let value) = inline {
            if value.isEmpty { return }
            if case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + value)
                return
            }
        }
        result.append(inline)
    }

    // MARK: - Links, images, autolinks

    private func parseLinkOrImage(
        _ characters: [Character],
        at start: Int,
        isImage: Bool
    ) -> (inline: MarkdownInline, nextIndex: Int)? {
        let openBracket: Int
        if isImage {
            guard start + 1 < characters.count,
                  characters[start] == "!", characters[start + 1] == "[" else {
                return nil
            }
            openBracket = start + 1
        } else {
            guard characters[start] == "[" else { return nil }
            openBracket = start
        }

        guard let closeBracket = findClosingBracket(characters, from: openBracket) else {
            return nil
        }
        let label = String(characters[(openBracket + 1)..<closeBracket])
        let cursor = closeBracket + 1
        var end = cursor

        var destination: String?
        var title: String?

        if cursor < characters.count, characters[cursor] == "(" {
            guard let target = MarkdownLinkSyntax.parseInlineLinkTarget(
                characters,
                from: cursor + 1
            ), target.end < characters.count, characters[target.end] == ")" else {
                return nil
            }
            destination = target.destination
            title = target.title
            end = target.end + 1
        } else if cursor < characters.count, characters[cursor] == "[" {
            guard let referenceClose = findClosingBracket(characters, from: cursor) else {
                return nil
            }
            let explicitLabel = String(characters[(cursor + 1)..<referenceClose])
            let key = MarkdownLinkSyntax.normalizeLabel(
                explicitLabel.isEmpty ? label : explicitLabel
            )
            guard let reference = references[key] else { return nil }
            destination = reference.destination
            title = reference.title
            end = referenceClose + 1
        } else {
            guard let reference = references[MarkdownLinkSyntax.normalizeLabel(label)] else {
                return nil
            }
            destination = reference.destination
            title = reference.title
        }

        guard let destination else { return nil }

        if isImage {
            let alt = MarkdownInlineParser(references: references).parse(label).plainText
            return (.image(source: destination, alt: alt, title: title), end)
        }

        let children = MarkdownInlineParser(references: references).parse(label)
        return (.link(destination: destination, title: title, children: children), end)
    }

    private func parseAngleBracket(
        _ characters: [Character],
        at start: Int
    ) -> (inline: MarkdownInline, nextIndex: Int)? {
        var cursor = start + 1
        var content = ""

        while cursor < characters.count {
            let character = characters[cursor]
            if character == ">" {
                let nextIndex = cursor + 1

                if isAutolinkURL(content) {
                    return (.link(
                        destination: content,
                        title: nil,
                        children: [.text(content)]
                    ), nextIndex)
                }
                if isEmailAddress(content) {
                    return (.link(
                        destination: "mailto:" + content,
                        title: nil,
                        children: [.text(content)]
                    ), nextIndex)
                }
                if let tag = inlineTagName(content) {
                    if tag == "br" {
                        return (.hardBreak, nextIndex)
                    }
                    return (.html("<\(content)>"), nextIndex)
                }
                return nil
            }
            if character == "\n" || character == "<" { return nil }
            content.append(character)
            cursor += 1
        }

        return nil
    }

    private func isAutolinkURL(_ content: String) -> Bool {
        guard !content.contains(where: { $0.isWhitespace }),
              let colon = content.firstIndex(of: ":") else {
            return false
        }
        let scheme = content[..<colon]
        guard (2...32).contains(scheme.count), scheme.first?.isLetter == true else {
            return false
        }
        return scheme.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-"
        }
    }

    private func isEmailAddress(_ content: String) -> Bool {
        guard !content.contains(where: { $0.isWhitespace }) else { return false }
        let parts = content.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }

        let local = parts[0]
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else {
            return false
        }

        let allowedLocal = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".!#$%&'*+/=?^_`{|}~-")
        )
        let validLocal = local.allSatisfy { character in
            character.unicodeScalars.allSatisfy { allowedLocal.contains($0) }
        }
        let validDomain = domain.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "." || $0 == "-"
        }
        return validLocal && validDomain
    }

    private func inlineTagName(_ content: String) -> String? {
        var body = content
        while body.hasSuffix("/") { body.removeLast() }
        if body.hasPrefix("/") { body.removeFirst() }

        guard let first = body.first, first.isLetter else { return nil }
        var name = ""
        for character in body {
            guard character.isLetter || character.isNumber || character == "-" else { break }
            name.append(character)
        }
        let rest = body.dropFirst(name.count)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        return name.lowercased()
    }

    /// Maps the handful of inline HTML tags that have a native text equivalent onto
    /// delimiter tokens, so `<em>word</em>` renders as emphasis and `<b>` as bold.
    /// Unknown tags stay as literal `.html` spans.
    private func formattingTag(
        from raw: String
    ) -> (kind: DelimiterKind, isClosing: Bool)? {
        guard raw.hasPrefix("<"), raw.hasSuffix(">") else { return nil }
        var content = String(raw.dropFirst().dropLast())
        guard !content.hasSuffix("/") else { return nil }

        let isClosing = content.hasPrefix("/")
        if isClosing { content.removeFirst() }
        guard !content.isEmpty,
              content.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return nil
        }

        switch content.lowercased() {
        case "b", "strong":
            return (.strong, isClosing)
        case "i", "em":
            return (.emphasis, isClosing)
        case "code":
            return (.code, isClosing)
        case "del", "s", "strike":
            return (.strikethrough, isClosing)
        default:
            return nil
        }
    }

    // MARK: - Character helpers

    private func countRun(
        _ characters: [Character],
        at start: Int,
        character: Character
    ) -> Int {
        var cursor = start
        while cursor < characters.count, characters[cursor] == character {
            cursor += 1
        }
        return cursor - start
    }

    private func findCodeClose(
        _ characters: [Character],
        from start: Int,
        run: Int
    ) -> Int? {
        var cursor = start
        while cursor < characters.count {
            if characters[cursor] == "`" {
                let length = countRun(characters, at: cursor, character: "`")
                if length == run { return cursor }
                cursor += length
            } else {
                cursor += 1
            }
        }
        return nil
    }

    /// Parses Obsidian-style `[[target]]` and `[[target|label]]` spans.
    private func parseWikiLink(
        _ characters: [Character],
        at start: Int
    ) -> (inline: MarkdownInline, nextIndex: Int)? {
        guard let parsed = parseBracketedWikiSpan(characters, at: start) else { return nil }
        return (
            inline: .wikiLink(target: parsed.target, label: parsed.label),
            nextIndex: parsed.nextIndex
        )
    }

    /// Parses Obsidian-style `![[target]]` transclusion spans.
    ///
    /// `![[Note]]` embeds the whole note, `![[Note#Heading]]` embeds one section, and
    /// `![[image.png]]` embeds an attachment. The `[` of the inner `[[` is at `start + 1`.
    private func parseEmbed(
        _ characters: [Character],
        at start: Int
    ) -> (inline: MarkdownInline, nextIndex: Int)? {
        guard start + 1 < characters.count,
              let parsed = parseBracketedWikiSpan(characters, at: start + 1) else {
            return nil
        }
        // `|640x480`-style dimension hints and arbitrary labels both collapse to the label
        // the preview shows when the target cannot be resolved.
        var label = parsed.label
        if label.range(of: #"^\d+(x\d+)?$"#, options: .regularExpression) != nil {
            label = parsed.target
        }
        return (
            inline: .embed(target: parsed.target, label: label),
            nextIndex: parsed.nextIndex
        )
    }

    /// Parses `[^label]` footnote references.
    private func parseFootnoteReference(
        _ characters: [Character],
        at start: Int
    ) -> (inline: MarkdownInline, nextIndex: Int)? {
        var index = start + 2
        var label = ""
        while index < characters.count {
            let character = characters[index]
            if character == "\n" { return nil }
            if character == "]" {
                let trimmed = label.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.contains("[") else { return nil }
                return (
                    inline: .footnoteReference(label: trimmed),
                    nextIndex: index + 1
                )
            }
            label.append(character)
            index += 1
        }
        return nil
    }

    /// Shared `[[target|label]]` scanner. `start` points at the first `[`.
    private func parseBracketedWikiSpan(
        _ characters: [Character],
        at start: Int
    ) -> (target: String, label: String, nextIndex: Int)? {
        guard start + 1 < characters.count,
              characters[start] == "[",
              characters[start + 1] == "[" else {
            return nil
        }

        var index = start + 2
        while index + 1 < characters.count {
            if characters[index] == "\n" { return nil }
            if characters[index] == "]", characters[index + 1] == "]" {
                let content = String(characters[(start + 2)..<index])
                let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let target = parts.first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !target.isEmpty else { return nil }

                let rawLabel = parts.count > 1
                    ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    : target
                let label = rawLabel.isEmpty ? target : rawLabel

                return (target: target, label: label, nextIndex: index + 2)
            }
            index += 1
        }
        return nil
    }

    private func findClosingBracket(
        _ characters: [Character],
        from open: Int
    ) -> Int? {
        guard open < characters.count, characters[open] == "[" else { return nil }
        var depth = 0
        var cursor = open + 1
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\", cursor + 1 < characters.count {
                cursor += 2
                continue
            }
            if character == "[" {
                depth += 1
            } else if character == "]" {
                if depth == 0 { return cursor }
                depth -= 1
            }
            cursor += 1
        }
        return nil
    }

    private func flanking(
        _ characters: [Character],
        at index: Int,
        run: Int,
        character: Character
    ) -> (canOpen: Bool, canClose: Bool) {
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + run < characters.count ? characters[index + run] : nil

        let previousWhitespace = previous?.isWhitespace ?? true
        let nextWhitespace = next?.isWhitespace ?? true
        let previousPunctuation = previous.map(isPunctuation) ?? false
        let nextPunctuation = next.map(isPunctuation) ?? false

        let leftFlanking = !nextWhitespace
            && (!nextPunctuation || previousWhitespace || previousPunctuation)
        let rightFlanking = !previousWhitespace
            && (!previousPunctuation || nextWhitespace || nextPunctuation)

        if character == "_" {
            return (
                leftFlanking && (!rightFlanking || previousPunctuation),
                rightFlanking && (!leftFlanking || nextPunctuation)
            )
        }
        return (leftFlanking, rightFlanking)
    }

    private func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }
}

private let markdownEscapableCharacters: Set<Character> = [
    "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".",
    "/", ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`",
    "{", "|", "}", "~",
]
