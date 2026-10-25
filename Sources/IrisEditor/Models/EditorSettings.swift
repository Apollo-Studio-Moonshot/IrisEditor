import AppKit
import SwiftUI

struct EditorSettings: Codable, Equatable {
    var fontFamily: String = "SF Mono"
    var fontSize: Double = 14
    var tabWidth: Int = 4
    var highlightCurrentLine: Bool = true
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false

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

    var tabInterval: CGFloat {
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        return max(1, spaceWidth * CGFloat(max(1, tabWidth)))
    }

    static func load() -> EditorSettings {
        guard let data = UserDefaults.standard.data(forKey: "IrisEditor.Settings"),
              let settings = try? JSONDecoder().decode(EditorSettings.self, from: data) else {
            return EditorSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "IrisEditor.Settings")
    }
}
