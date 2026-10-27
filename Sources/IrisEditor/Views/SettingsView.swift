import AppKit
import SwiftUI

/// Native macOS Settings pane presented by the `Settings` scene (⌘,).
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section(L10n.editorFont) {
                Picker(L10n.family, selection: $appState.settings.fontFamily) {
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
                        Text(L10n.size)
                        Spacer()
                        Text("\(Int(appState.settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.display) {
                Toggle(L10n.showLineNumbers, isOn: $appState.settings.showLineNumbers)
                Toggle(L10n.highlightCurrentLine, isOn: $appState.settings.highlightCurrentLine)
                Toggle(L10n.wrapLines, isOn: $appState.settings.wordWrap)
            }

            Section(L10n.appearance) {
                Picker(L10n.accent, selection: $appState.settings.accent) {
                    ForEach(AccentTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                Picker(L10n.previewTheme, selection: $appState.settings.previewTheme) {
                    ForEach(PreviewTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.writing) {
                Toggle(L10n.typewriterScrolling, isOn: $appState.settings.typewriterMode)
                Toggle(L10n.focusMode, isOn: $appState.settings.focusMode)
                Toggle(L10n.smartTableNavigation, isOn: $appState.settings.smartTableNavigation)
                Toggle(L10n.wikiAutocomplete, isOn: $appState.settings.wikiAutocomplete)
            }

            Section(L10n.keybindings) {
                ForEach(KeybindingCommand.allCases) { command in
                    KeybindingRow(command: command)
                }

                Button(L10n.resetAllKeybindings) {
                    appState.resetKeybindings()
                }
                .disabled(appState.settings.keybindingOverrides.isEmpty)
            }

            Section(L10n.vaultSection) {
                HStack {
                    Text(appState.effectiveVaultRoot?.path ?? L10n.noFolderSelected)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.choose) {
                        appState.chooseVaultFolder()
                    }
                }
                Button(L10n.useCurrentFolder) {
                    appState.useCurrentFolderAsVault()
                }
                .disabled(appState.document.fileURL == nil)
            }

            Section(L10n.aiProvider) {
                Picker(L10n.provider, selection: $appState.settings.aiConfiguration.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appState.settings.aiConfiguration.provider) { _, newProvider in
                    appState.settings.aiConfiguration.model = ""
                    appState.settings.aiConfiguration.baseURL = ""
                    if newProvider.isRemote {
                        appState.settings.aiConfiguration.model = newProvider.defaultModel
                        appState.settings.aiConfiguration.baseURL = newProvider.defaultBaseURL
                    }
                }

                if appState.settings.aiConfiguration.provider.isRemote {
                    SecureField(L10n.apiKey, text: $appState.settings.aiConfiguration.apiKey)
                        .accessibilityIdentifier("Settings.AIAPIKey")

                    TextField(
                        L10n.model,
                        text: $appState.settings.aiConfiguration.model,
                        prompt: Text(appState.settings.aiConfiguration.provider.defaultModel)
                    )
                    .accessibilityIdentifier("Settings.AIModel")

                    TextField(
                        L10n.baseURL,
                        text: $appState.settings.aiConfiguration.baseURL,
                        prompt: Text(appState.settings.aiConfiguration.provider.defaultBaseURL)
                    )
                    .accessibilityIdentifier("Settings.AIBaseURL")

                    Text(L10n.apiKeyKeychainNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.ai.isAvailable ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(appState.ai.availabilityDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.indentation) {
                Picker(L10n.tabWidth, selection: $appState.settings.tabWidth) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.previewSection) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hello, Iris Editor")
                    Text("# Heading · **bold** · *italic* · `code`")
                        .foregroundStyle(.secondary)
                }
                .font(.custom(appState.settings.fontFamily, size: appState.settings.fontSize))
                .padding(.vertical, 8)
            }

            Section(L10n.accessibilitySection) {
                Text(L10n.accessibilityAuditSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(accessibilityAuditItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(item)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 780)
    }

    private var accessibilityAuditItems: [String] {
        [
            L10n.sidebarAudit,
            L10n.suggestionAudit,
            L10n.searchAudit,
            L10n.dialogAudit,
            L10n.editorAudit
        ]
    }
}

/// One editable shortcut row: shows the effective key, accepts a string such as
/// `"control+option+v"`, and can be reset to the command's default.
private struct KeybindingRow: View {
    @EnvironmentObject private var appState: AppState
    let command: KeybindingCommand

    @State private var draft = ""
    @State private var isInvalid = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command.title)
                .font(.system(size: 12))

            Spacer()

            Text(appState.keybindingLabel(for: command))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                .accessibilityLabel(L10n.shortcutLabel(command.title))

            TextField(L10n.keybindingFieldPlaceholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 160)
                .onSubmit(apply)
                .accessibilityLabel(L10n.newShortcutField(command.title))

            if isInvalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help(L10n.invalidKeybinding)
            }

            Button(L10n.resetKeybinding) {
                appState.setKeybindingOverride(nil, for: command)
                draft = ""
                isInvalid = false
            }
            .controlSize(.small)
            .disabled(appState.settings.keybindingOverrides[command.rawValue] == nil)
            .accessibilityLabel(L10n.resetShortcut(command.title))
        }
    }

    private func apply() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if appState.setKeybindingOverride(draft, for: command) {
            draft = ""
            isInvalid = false
        } else {
            isInvalid = true
        }
    }
}
