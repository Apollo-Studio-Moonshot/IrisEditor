import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    private let fontFamilies = [
        "SF Mono", "Menlo", "Monaco", "Consolas", "Courier New",
        "JetBrains Mono", "Fira Code", "Source Code Pro"
    ]
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.18, blue: 0.25),
                    Color(red: 0.10, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                
                // Settings content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // MARK: - Font Section
                        SettingsSectionHeader(title: "Editor Font", icon: "textformat")
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Font Family")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $appState.settings.fontFamily) {
                                    ForEach(fontFamilies, id: \.self) { family in
                                        Text(family).tag(family)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                            }
                            
                            HStack {
                                Text("Font Size")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Stepper(
                                    value: $appState.settings.fontSize,
                                    in: 8...32,
                                    step: 1
                                ) {
                                    Text("\(Int(appState.settings.fontSize)) pt")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .frame(width: 50)
                                }
                                .frame(width: 180)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                        
                        // MARK: - Display Section
                        SettingsSectionHeader(title: "Display", icon: "eye")
                        
                        VStack(spacing: 12) {
                            Toggle("Highlight Current Line", isOn: $appState.settings.highlightCurrentLine)
                                .toggleStyle(.switch)
                                .font(.system(size: 13))
                            
                            Toggle("Show Line Numbers", isOn: $appState.settings.showLineNumbers)
                                .toggleStyle(.switch)
                                .font(.system(size: 13))
                            
                            Toggle("Word Wrap", isOn: $appState.settings.wordWrap)
                                .toggleStyle(.switch)
                                .font(.system(size: 13))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                        
                        // MARK: - Indentation Section
                        SettingsSectionHeader(title: "Indentation", icon: "arrow.right.arrow.left")
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Tab Width")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $appState.settings.tabWidth) {
                                    Text("2 spaces").tag(2)
                                    Text("4 spaces").tag(4)
                                    Text("6 spaces").tag(6)
                                    Text("8 spaces").tag(8)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                        
                        // MARK: - Preview
                        SettingsSectionHeader(title: "Preview", icon: "sparkles")
                        
                        VStack {
                            Text("Hello, Iris Editor!")
                                .font(
                                    .custom(
                                        appState.settings.fontFamily,
                                        size: appState.settings.fontSize
                                    )
                                )
                                .foregroundStyle(.primary)
                            Text("func example() { return \"Liquid Glass\" }")
                                .font(
                                    .custom(
                                        appState.settings.fontFamily,
                                        size: appState.settings.fontSize * 0.9
                                    )
                                )
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .padding(24)
                }
            }
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
        }
    }
}
