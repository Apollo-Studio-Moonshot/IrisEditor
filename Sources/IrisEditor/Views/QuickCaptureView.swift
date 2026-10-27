import SwiftUI

/// Menu-bar quick capture panel: jot a thought and file it into the vault's Inbox.
struct QuickCaptureView: View {
    @EnvironmentObject private var appState: AppState
    @State private var text = ""
    @State private var justSaved = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(L10n.quickCapture)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if justSaved {
                    Label(L10n.saved, systemImage: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                .focused($isFocused)
                .accessibilityLabel(L10n.quickCapture)
                .accessibilityIdentifier("QuickCapture.Editor")

            HStack {
                Text(appState.effectiveVaultRoot?.lastPathComponent ?? L10n.newTab)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button(L10n.capture) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L10n.capture)
                .accessibilityIdentifier("QuickCapture.Save")
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { isFocused = true }
    }

    private func save() {
        appState.saveQuickCapture(text)
        text = ""
        withAnimation(.snappy(duration: 0.2)) {
            justSaved = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.2)) {
                justSaved = false
            }
        }
    }
}
