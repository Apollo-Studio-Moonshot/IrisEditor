import SwiftUI

/// Local version history browser with a read-only snapshot preview and restore action.
struct VersionHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.versionHistory.isEmpty {
                Text(L10n.versionsHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    versionList
                        .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
                    previewPane
                        .frame(minWidth: 320)
                }
            }

            Divider()
            footer
        }
        .frame(width: 760, height: 500)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
        .onAppear {
            appState.refreshVersionHistory()
            selectedID = appState.versionHistory.first?.id
        }
        .onExitCommand { appState.dismissVersionHistory() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(L10n.versionHistoryTitle)
                .font(.system(size: 13, weight: .semibold))
            Text(appState.document.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button {
                appState.dismissVersionHistory()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(L10n.closeVersionHistory)
            .accessibilityIdentifier("VersionHistory.Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var versionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(appState.versionHistory) { version in
                    Button {
                        selectedID = version.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatted(version.savedAt))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.charactersInSnapshot(version.text.count))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selectedID == version.id
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(formatted(version.savedAt))
                    .accessibilityValue(L10n.charactersInSnapshot(version.text.count))
                    .accessibilityIdentifier("VersionHistory.Version.\(version.id.uuidString)")
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let version = selectedVersion {
            ScrollView {
                Text(version.text.isEmpty ? L10n.emptySnapshot : version.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } else {
            Text(L10n.selectVersionHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text(L10n.snapshots(appState.versionHistory.count))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(L10n.restore) {
                guard let version = selectedVersion else { return }
                appState.restoreVersion(version)
            }
            .disabled(selectedVersion == nil)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(L10n.restore)
            .accessibilityIdentifier("VersionHistory.Restore")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var selectedVersion: DocumentVersion? {
        appState.versionHistory.first { $0.id == selectedID }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
