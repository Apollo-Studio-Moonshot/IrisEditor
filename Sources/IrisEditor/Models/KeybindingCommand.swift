import SwiftUI

/// Menu commands whose keyboard shortcuts can be re-bound from Settings.
///
/// Destructive or safety-critical shortcuts (Save, Save As, Quit) are deliberately
/// absent so a bad override can never make it impossible to save or exit.
enum KeybindingCommand: String, CaseIterable, Identifiable {
    case newTab
    case openDocument
    case closeTab
    case reopenClosedTab
    case nextTab
    case previousTab
    case printDocument
    case quickSwitcher
    case commandPalette
    case toggleOutline
    case zenMode
    case versionHistory
    case pasteAsMarkdown
    case exportHTML
    case exportPDF
    case findReplace
    case goToLine
    case zoomIn
    case zoomOut
    case actualSize
    case bold
    case italic
    case inlineCode
    case togglePreview
    case inlineCompletion
    case rewriteSelection
    case newNote
    case vaultSearch
    case dailyNote
    case toggleStar
    case openGraphWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: return "New Tab"
        case .openDocument: return "Open…"
        case .closeTab: return "Close Tab"
        case .reopenClosedTab: return "Reopen Closed Tab"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        case .printDocument: return "Print…"
        case .quickSwitcher: return "Quick Switcher…"
        case .commandPalette: return "Command Palette…"
        case .toggleOutline: return "Toggle Outline"
        case .zenMode: return "Zen Mode"
        case .versionHistory: return "Version History…"
        case .pasteAsMarkdown: return "Paste as Markdown"
        case .exportHTML: return "Export as HTML…"
        case .exportPDF: return "Export as PDF…"
        case .findReplace: return "Find & Replace…"
        case .goToLine: return "Go to Line…"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .actualSize: return "Actual Size"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .inlineCode: return "Inline Code"
        case .togglePreview: return "Toggle Preview"
        case .inlineCompletion: return "Inline Completion"
        case .rewriteSelection: return "Rewrite Selection…"
        case .newNote: return "New Note…"
        case .vaultSearch: return "Search All Notes…"
        case .dailyNote: return "Daily Note"
        case .toggleStar: return "Star Note"
        case .openGraphWindow: return "Open Graph Window"
        }
    }

    /// Canonical, normalized shortcut string shown during editing.
    var defaultKeyString: String {
        switch self {
        case .newTab: return "command+t"
        case .openDocument: return "command+o"
        case .closeTab: return "command+w"
        case .reopenClosedTab: return "command+shift+t"
        case .nextTab: return "command+shift+]"
        case .previousTab: return "command+shift+["
        case .printDocument: return "command+option+shift+p"
        case .quickSwitcher: return "command+p"
        case .commandPalette: return "command+shift+p"
        case .toggleOutline: return "command+shift+o"
        case .zenMode: return "control+command+z"
        case .versionHistory: return "command+shift+h"
        case .pasteAsMarkdown: return "command+option+v"
        case .exportHTML: return "command+shift+e"
        case .exportPDF: return "command+option+e"
        case .findReplace: return "command+f"
        case .goToLine: return "command+g"
        case .zoomIn: return "command+="
        case .zoomOut: return "command+-"
        case .actualSize: return "command+0"
        case .bold: return "command+b"
        case .italic: return "command+i"
        case .inlineCode: return "command+k"
        case .togglePreview: return "command+option+p"
        case .inlineCompletion: return "control+space"
        case .rewriteSelection: return "command+option+r"
        case .newNote: return "command+shift+n"
        case .vaultSearch: return "command+shift+f"
        case .dailyNote: return "command+shift+d"
        case .toggleStar: return "command+shift+s"
        case .openGraphWindow: return "command+shift+g"
        }
    }

    var defaultShortcut: KeyboardShortcut? {
        KeybindingParser.shortcut(from: defaultKeyString)
    }
}

/// Parses human-entered shortcut strings such as `"control+option+v"` into a
/// `KeyboardShortcut`, and formats them back for display.
enum KeybindingParser {
    static func shortcut(from raw: String) -> KeyboardShortcut? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var modifiers: EventModifiers = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "command", "cmd", "\u{2318}":
                modifiers.insert(.command)
            case "shift", "\u{21E7}":
                modifiers.insert(.shift)
            case "option", "alt", "opt", "\u{2325}":
                modifiers.insert(.option)
            case "control", "ctrl", "\u{2303}":
                modifiers.insert(.control)
            default:
                // Only one non-modifier key is allowed.
                guard keyPart == nil else { return nil }
                keyPart = part
            }
        }

        guard let keyPart,
              let equivalent = keyEquivalent(for: keyPart) else { return nil }
        // Require a command or control modifier so bindings never shadow typing.
        guard modifiers.contains(.command) || modifiers.contains(.control) else { return nil }

        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }

    /// Returns the canonical form of a shortcut string, or nil when it is invalid.
    static func normalized(_ raw: String) -> String? {
        guard let shortcut = shortcut(from: raw) else { return nil }
        var pieces: [String] = []
        if shortcut.modifiers.contains(.control) { pieces.append("control") }
        if shortcut.modifiers.contains(.option) { pieces.append("option") }
        if shortcut.modifiers.contains(.shift) { pieces.append("shift") }
        if shortcut.modifiers.contains(.command) { pieces.append("command") }

        let key = keyName(for: shortcut.key)
        pieces.append(key)
        return pieces.joined(separator: "+")
    }

    /// Compact glyph label for menus and settings rows, e.g. `"⌃⌘Z"`.
    static func displayName(_ raw: String) -> String {
        guard let shortcut = shortcut(from: raw) else { return raw }
        var label = ""
        if shortcut.modifiers.contains(.control) { label += "\u{2303}" }
        if shortcut.modifiers.contains(.option) { label += "\u{2325}" }
        if shortcut.modifiers.contains(.shift) { label += "\u{21E7}" }
        if shortcut.modifiers.contains(.command) { label += "\u{2318}" }

        let key: String
        switch shortcut.key.character {
        case KeyEquivalent.upArrow.character: key = "\u{2191}"
        case KeyEquivalent.downArrow.character: key = "\u{2193}"
        case KeyEquivalent.leftArrow.character: key = "\u{2190}"
        case KeyEquivalent.rightArrow.character: key = "\u{2192}"
        case KeyEquivalent.space.character: key = "Space"
        case KeyEquivalent.return.character: key = "\u{21A9}"
        case KeyEquivalent.tab.character: key = "\u{21E5}"
        case KeyEquivalent.escape.character: key = "\u{238B}"
        case KeyEquivalent.delete.character: key = "\u{232B}"
        default: key = String(shortcut.key.character).uppercased()
        }
        return label + key
    }

    private static func keyName(for key: KeyEquivalent) -> String {
        switch key.character {
        case KeyEquivalent.upArrow.character: return "up"
        case KeyEquivalent.downArrow.character: return "down"
        case KeyEquivalent.leftArrow.character: return "left"
        case KeyEquivalent.rightArrow.character: return "right"
        case KeyEquivalent.space.character: return "space"
        case KeyEquivalent.return.character: return "return"
        case KeyEquivalent.tab.character: return "tab"
        case KeyEquivalent.escape.character: return "escape"
        case KeyEquivalent.delete.character: return "delete"
        default: return String(key.character)
        }
    }

    private static func keyEquivalent(for key: String) -> KeyEquivalent? {
        switch key {
        case "space", "spacebar": return .space
        case "tab": return .tab
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "up", "arrowup": return .upArrow
        case "down", "arrowdown": return .downArrow
        case "left", "arrowleft": return .leftArrow
        case "right", "arrowright": return .rightArrow
        default:
            guard key.count == 1, let character = key.first else { return nil }
            return KeyEquivalent(character)
        }
    }
}
