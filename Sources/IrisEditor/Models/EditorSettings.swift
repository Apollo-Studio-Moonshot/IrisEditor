import AppKit
import SwiftUI

/// Accent tint applied to controls, selection highlights, and link chips.
enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case systemBlue, systemPurple, systemTeal, systemPink
    case systemOrange, systemGreen, systemIndigo, graphite
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemBlue: return "Blue"
        case .systemPurple: return "Purple"
        case .systemTeal: return "Teal"
        case .systemPink: return "Pink"
        case .systemOrange: return "Orange"
        case .systemGreen: return "Green"
        case .systemIndigo: return "Indigo"
        case .graphite: return "Graphite"
        case .custom: return "Custom"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .systemBlue: return .systemBlue
        case .systemPurple: return .systemPurple
        case .systemTeal: return .systemTeal
        case .systemPink: return .systemPink
        case .systemOrange: return .systemOrange
        case .systemGreen: return .systemGreen
        case .systemIndigo: return .systemIndigo
        case .graphite: return .systemGray
        case .custom: return .systemBlue
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Parses `#RRGGBB` or `#RGB` so plugins and the color picker share one format.
    static func color(fromHex raw: String) -> Color? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hexString(from color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#4A90E2" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}

/// Window appearance chosen in Settings. High Contrast pins a dark, stronger-bordered
/// palette that works well on projectors and in bright rooms.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark, highContrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .highContrast: return "High Contrast"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .highContrast: return "circle.righthalf.filled.inverse"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .highContrast: return .dark
        }
    }

    var isHighContrast: Bool { self == .highContrast }
}

/// Keyboard model for the editor. `standard` keeps native macOS behavior; the modal
/// and Emacs options are implemented in `VimEngine` and `IrisTextView`.
enum EditingMode: String, Codable, CaseIterable, Identifiable {
    case standard, vim, emacs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .vim: return "Vim"
        case .emacs: return "Emacs"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Native macOS text editing and shortcuts."
        case .vim: return "Modal editing: Normal, Insert, Visual, and command-line modes."
        case .emacs: return "Control and Option key navigation and kill/yank."
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "keyboard"
        case .vim: return "character.cursor.ibeam"
        case .emacs: return "option"
        }
    }
}

/// Colour treatment for the rendered Markdown preview.
enum PreviewTheme: String, Codable, CaseIterable, Identifiable {
    case system, paper, sepia, midnight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .midnight: return "Midnight"
        }
    }

    var background: Color {
        switch self {
        case .system: return Color(nsColor: .textBackgroundColor)
        case .paper: return Color(red: 0.99, green: 0.985, blue: 0.97)
        case .sepia: return Color(red: 0.96, green: 0.92, blue: 0.84)
        case .midnight: return Color(red: 0.10, green: 0.11, blue: 0.15)
        }
    }

    var text: Color {
        switch self {
        case .system: return .primary
        case .paper: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .sepia: return Color(red: 0.24, green: 0.19, blue: 0.12)
        case .midnight: return Color(red: 0.86, green: 0.88, blue: 0.94)
        }
    }

    /// Backing colour for `==highlight==`, tuned per theme so it stays readable.
    var highlightBackground: Color {
        switch self {
        case .system: return Color.yellow.opacity(0.35)
        case .paper: return Color(red: 1.0, green: 0.92, blue: 0.55)
        case .sepia: return Color(red: 0.98, green: 0.87, blue: 0.52)
        case .midnight: return Color(red: 0.55, green: 0.45, blue: 0.08)
        }
    }

    var secondary: Color {
        switch self {
        case .system: return .secondary
        case .paper: return Color(red: 0.42, green: 0.42, blue: 0.44)
        case .sepia: return Color(red: 0.44, green: 0.36, blue: 0.25)
        case .midnight: return Color(red: 0.58, green: 0.62, blue: 0.72)
        }
    }

    var surface: Color {
        switch self {
        case .system: return Color(nsColor: .quaternaryLabelColor).opacity(0.5)
        case .paper: return Color(red: 0.94, green: 0.93, blue: 0.90)
        case .sepia: return Color(red: 0.90, green: 0.85, blue: 0.75)
        case .midnight: return Color(red: 0.16, green: 0.17, blue: 0.23)
        }
    }

    var border: Color {
        switch self {
        case .system: return Color(nsColor: .separatorColor)
        case .paper: return Color(red: 0.82, green: 0.81, blue: 0.78)
        case .sepia: return Color(red: 0.78, green: 0.72, blue: 0.60)
        case .midnight: return Color(red: 0.24, green: 0.26, blue: 0.34)
        }
    }

    var isDark: Bool { self == .midnight }
}

struct EditorSettings: Codable, Equatable {
    var fontFamily: String = "SF Mono"
    var fontSize: Double = 14
    var tabWidth: Int = 4
    var highlightCurrentLine: Bool = true
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false

    // Appearance
    var appearance: AppAppearance = .system
    var accent: AccentTheme = .systemBlue
    var accentHex: String = "#4A90E2"
    var previewTheme: PreviewTheme = .system

    // Writing modes
    var typewriterMode: Bool = false
    var focusMode: Bool = false
    var smartTableNavigation: Bool = true
    var wikiAutocomplete: Bool = true
    var editingMode: EditingMode = .standard

    // Sidebar
    /// Which listing the files pane shows: folded tree, recent notes, or all notes.
    var vaultFileListing: VaultFileListing = .tree
    var vaultFileSort: VaultFileSort = .name
    /// Ascending order for the name sort; date and size sorts start newest/largest first.
    var vaultFileSortAscending: Bool = true
    /// Folder sections expanded in the files pane, keyed by relative path.
    var collapsedSidebarFolders: [String] = []

    // Plugins
    var disabledPluginIDs: [String] = []

    /// Command id → canonical shortcut string, e.g. `"zenMode": "control+command+z"`.
    var keybindingOverrides: [String: String] = [:]

    /// AI backend used by the writing assistant.
    var aiConfiguration = AIProviderConfiguration()

    static let defaultFontSize: Double = 14

    static let fontFamilies = [
        "SF Mono", "Menlo", "Monaco", "Courier New",
        "Andale Mono", "Consolas", "JetBrains Mono",
        "Fira Code", "Source Code Pro"
    ]

    var font: NSFont {
        NSFont(name: fontFamily, size: CGFloat(fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    }

    var lineNumberFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: max(9, CGFloat(fontSize) - 2), weight: .regular)
    }

    var swiftUIFont: Font {
        Font.custom(fontFamily, size: fontSize)
    }

    /// The accent actually painted in the UI, resolving the custom hex when needed.
    var accentColor: Color {
        if accent == .custom {
            return AccentTheme.color(fromHex: accentHex) ?? .accentColor
        }
        return accent.color
    }

    var isHighContrast: Bool { appearance.isHighContrast }

    var tabInterval: CGFloat {
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        return max(1, spaceWidth * CGFloat(max(1, tabWidth)))
    }

    // MARK: - Codable with forward-compatible defaults

    init() {}

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, tabWidth, highlightCurrentLine
        case showLineNumbers, wordWrap, appearance, accent, accentHex, previewTheme
        case typewriterMode, focusMode, smartTableNavigation, wikiAutocomplete
        case editingMode, disabledPluginIDs, keybindingOverrides, aiConfiguration
        case vaultFileListing, vaultFileSort, vaultFileSortAscending, collapsedSidebarFolders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EditorSettings()
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
            ?? defaults.fontFamily
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
            ?? defaults.fontSize
        tabWidth = try container.decodeIfPresent(Int.self, forKey: .tabWidth)
            ?? defaults.tabWidth
        highlightCurrentLine = try container.decodeIfPresent(Bool.self, forKey: .highlightCurrentLine)
            ?? defaults.highlightCurrentLine
        showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers)
            ?? defaults.showLineNumbers
        wordWrap = try container.decodeIfPresent(Bool.self, forKey: .wordWrap)
            ?? defaults.wordWrap
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance)
            ?? defaults.appearance
        accent = try container.decodeIfPresent(AccentTheme.self, forKey: .accent)
            ?? defaults.accent
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex)
            ?? defaults.accentHex
        previewTheme = try container.decodeIfPresent(PreviewTheme.self, forKey: .previewTheme)
            ?? defaults.previewTheme
        typewriterMode = try container.decodeIfPresent(Bool.self, forKey: .typewriterMode)
            ?? defaults.typewriterMode
        focusMode = try container.decodeIfPresent(Bool.self, forKey: .focusMode)
            ?? defaults.focusMode
        smartTableNavigation = try container.decodeIfPresent(Bool.self, forKey: .smartTableNavigation)
            ?? defaults.smartTableNavigation
        wikiAutocomplete = try container.decodeIfPresent(Bool.self, forKey: .wikiAutocomplete)
            ?? defaults.wikiAutocomplete
        editingMode = try container.decodeIfPresent(EditingMode.self, forKey: .editingMode)
            ?? defaults.editingMode
        disabledPluginIDs = try container.decodeIfPresent([String].self, forKey: .disabledPluginIDs)
            ?? defaults.disabledPluginIDs
        keybindingOverrides = try container.decodeIfPresent(
            [String: String].self,
            forKey: .keybindingOverrides
        ) ?? defaults.keybindingOverrides
        aiConfiguration = try container.decodeIfPresent(
            AIProviderConfiguration.self,
            forKey: .aiConfiguration
        ) ?? defaults.aiConfiguration
        vaultFileListing = try container.decodeIfPresent(
            VaultFileListing.self,
            forKey: .vaultFileListing
        ) ?? defaults.vaultFileListing
        vaultFileSort = try container.decodeIfPresent(
            VaultFileSort.self,
            forKey: .vaultFileSort
        ) ?? defaults.vaultFileSort
        vaultFileSortAscending = try container.decodeIfPresent(
            Bool.self,
            forKey: .vaultFileSortAscending
        ) ?? defaults.vaultFileSortAscending
        collapsedSidebarFolders = try container.decodeIfPresent(
            [String].self,
            forKey: .collapsedSidebarFolders
        ) ?? defaults.collapsedSidebarFolders
    }

    static func load() -> EditorSettings {
        var settings: EditorSettings
        if let data = UserDefaults.standard.data(forKey: "IrisEditor.Settings"),
           let decoded = try? JSONDecoder().decode(EditorSettings.self, from: data) {
            settings = decoded
        } else {
            settings = EditorSettings()
        }
        // The API key lives in the Keychain, never in the UserDefaults payload.
        settings.aiConfiguration.apiKey = AICredentialStore.loadAPIKey()
        return settings
    }

    func save() {
        AICredentialStore.saveAPIKey(aiConfiguration.apiKey)
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "IrisEditor.Settings")
    }
}
