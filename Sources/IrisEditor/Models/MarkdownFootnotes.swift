import Foundation

/// Assigns footnote numbers to `[^label]` references in document order.
///
/// The preview and the HTML export both walk a `MarkdownDocument` linearly, so numbering
/// is computed once from the block tree instead of being accumulated while rendering.
/// References without a matching definition are ignored (they render as literal text).
enum MarkdownFootnoteIndex {

    /// Labels that have a `[^label]: …` definition, in reference order, keyed by number.
    static func numbers(in document: MarkdownDocument) -> [String: Int] {
        var numbers: [String: Int] = [:]
        var next = 1
        let defined = Set(document.footnotes.map(\.label))

        func visit(_ inlines: [MarkdownInline]) {
            for inline in inlines {
                switch inline {
                case .footnoteReference(let label):
                    guard defined.contains(label), numbers[label] == nil else { continue }
                    numbers[label] = next
                    next += 1
                case .emphasis(let children), .strong(let children),
                     .strikethrough(let children), .highlight(let children):
                    visit(children)
                case .link(_, _, let children):
                    visit(children)
                default:
                    continue
                }
            }
        }

        func visitBlocks(_ blocks: [MarkdownBlock]) {
            let parser = MarkdownInlineParser(references: document.references)
            for block in blocks {
                switch block {
                case .heading(_, let text), .paragraph(let text):
                    visit(parser.parse(text))
                case .blockQuote(let children):
                    visitBlocks(children)
                case .list(_, _, let items):
                    for item in items {
                        visitBlocks(item.blocks)
                    }
                case .table(let header, _, let rows):
                    for cell in header { visit(parser.parse(cell)) }
                    for row in rows {
                        for cell in row { visit(parser.parse(cell)) }
                    }
                case .codeBlock, .thematicBreak, .htmlBlock:
                    continue
                }
            }
        }

        visitBlocks(document.blocks)
        return numbers
    }

    /// Footnotes in the order their references appear, with unresolved definitions dropped.
    static func orderedFootnotes(for document: MarkdownDocument) -> [(number: Int, footnote: MarkdownFootnote)] {
        let numbers = numbers(in: document)
        return document.footnotes
            .compactMap { footnote -> (number: Int, footnote: MarkdownFootnote)? in
                guard let number = numbers[footnote.label] else { return nil }
                return (number, footnote)
            }
            .sorted { $0.number < $1.number }
    }
}
