import Foundation

/// Line-aware editing helpers for the AppKit text view.
///
/// These are pure functions so list/quote continuation can be unit-tested without
/// instantiating `NSTextView`.
enum MarkdownEditing {

    /// What Return should do when the caret sits in a list or block quote.
    enum ReturnAction: Equatable {
        /// Insert a newline followed by `prefix` (already including indentation).
        case continueLine(prefix: String)

        /// The current list/quote item is empty: remove the marker and keep `indentation`.
        case endContainer(clearRange: NSRange, indentation: String)
    }

    /// Decides how Return should behave for `line` (without its line terminator).
    ///
    /// `caretOffset` is measured in UTF-16 units from the start of the line, matching
    /// `NSTextView.selectedRange()`. A container is only continued when the caret is
    /// after its marker, so pressing Return inside a marker behaves like plain text.
    static func returnAction(forLine line: String, caretOffset: Int) -> ReturnAction? {
        let ns = line as NSString
        guard caretOffset >= 0, caretOffset <= ns.length else { return nil }

        var cursor = 0
        while cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) {
            cursor += 1
        }
        let indentation = ns.substring(with: NSRange(location: 0, length: cursor))
        guard cursor < ns.length else { return nil }

        let first = ns.character(at: cursor)
        let continuation: String

        if first == 62 { // '>'
            var levels = 0
            while cursor < ns.length, ns.character(at: cursor) == 62 {
                cursor += 1
                levels += 1
                if cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) {
                    cursor += 1
                }
            }
            continuation = String(repeating: "> ", count: max(1, levels))
        } else if first == 45 || first == 42 || first == 43 { // '-', '*', '+'
            let marker = ns.substring(with: NSRange(location: cursor, length: 1))
            cursor += 1
            guard cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) else { return nil }
            while cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) {
                cursor += 1
            }

            if isTaskListMarker(in: ns, at: cursor) {
                cursor += 3 // "[ ]" / "[x]"
                while cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) {
                    cursor += 1
                }
                continuation = marker + " [ ] "
            } else {
                continuation = marker + " "
            }
        } else if isDigit(first) {
            let digitsStart = cursor
            while cursor < ns.length, isDigit(ns.character(at: cursor)) {
                cursor += 1
            }
            let digitsEnd = cursor
            guard cursor < ns.length,
                  ns.character(at: cursor) == 46 || ns.character(at: cursor) == 41, // '.' or ')'
                  cursor > digitsStart else {
                return nil
            }
            let delimiter = ns.substring(with: NSRange(location: cursor, length: 1))
            let digits = ns.substring(
                with: NSRange(location: digitsStart, length: digitsEnd - digitsStart)
            )
            cursor += 1
            guard cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) else { return nil }
            while cursor < ns.length, isSpaceOrTab(ns.character(at: cursor)) {
                cursor += 1
            }
            guard let number = Int(digits) else { return nil }
            continuation = "\(number + 1)\(delimiter) "
        } else {
            return nil
        }

        let markerRange = NSRange(location: 0, length: cursor)
        guard caretOffset >= markerRange.length else { return nil }

        let content = ns.substring(from: cursor)
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .endContainer(clearRange: markerRange, indentation: indentation)
        }
        return .continueLine(prefix: indentation + continuation)
    }

    private static func isTaskListMarker(in ns: NSString, at index: Int) -> Bool {
        guard index + 2 < ns.length,
              ns.character(at: index) == 91, // '['
              ns.character(at: index + 2) == 93 else { // ']'
            return false
        }
        let status = ns.character(at: index + 1)
        return status == 32 || status == 120 || status == 88 // space, x, X
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 48 && character <= 57
    }

    private static func isSpaceOrTab(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }
}
