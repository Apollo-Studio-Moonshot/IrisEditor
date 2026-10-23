import Foundation
import SwiftUI

struct EditorSettings: Codable {
    var fontFamily: String = "SF Mono"
    var fontSize: Double = 14
    var tabWidth: Int = 4
    var highlightCurrentLine: Bool = true
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false
    
    var font: NSFont {
        NSFont(name: fontFamily, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    }
    
    var swiftUIFont: Font {
        Font.custom(fontFamily, size: fontSize)
    }
    
    static func load() -> EditorSettings {
        guard let data = UserDefaults.standard.data(forKey: "IrisEditor.Settings"),
              let settings = try? JSONDecoder().decode(EditorSettings.self, from: data) else {
            return EditorSettings()
        }
        return settings
    }
}
