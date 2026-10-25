import AppKit
import SwiftUI

/// Native macOS Settings pane presented by the `Settings` scene (⌘,).
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Editor Font") {
                Picker("Family", selection: $appState.settings.fontFamily) {
                    ForEach(EditorSettings.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                Stepper(
                    value: $appState.settings.fontSize,
                    in: 8...32,
                    step: 1
                ) {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int(appState.settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Display") {
                Toggle("Show Line Numbers", isOn: $appState.settings.showLineNumbers)
                Toggle("Highlight Current Line", isOn: $appState.settings.highlightCurrentLine)
                Toggle("Wrap Lines", isOn: $appState.settings.wordWrap)
            }

            Section("Indentation") {
                Picker("Tab Width", selection: $appState.settings.tabWidth) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hello, Iris Editor")
                    Text("# Heading · **bold** · *italic* · `code`")
                        .foregroundStyle(.secondary)
                }
                .font(.custom(appState.settings.fontFamily, size: appState.settings.fontSize))
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 540)
    }
}
