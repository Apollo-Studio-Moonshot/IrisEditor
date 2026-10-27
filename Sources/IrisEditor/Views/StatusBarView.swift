import SwiftUI

/// Native status bar that sits below the editor and reads from the shared app state.
struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            item(L10n.cursorPosition(line: appState.cursorLine, column: appState.cursorColumn))
            separator
            item(lineCountText)
            separator
            item(wordCountText)
            separator
            item(characterCountText)

            Spacer(minLength: 12)

            if appState.document.isDirty {
                item(L10n.edited)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                separator
                    .transition(.opacity)
            }
            item(appState.document.fileSizeDescription)
            separator
            item(L10n.utf8)
        }
        .animation(.snappy(duration: 0.18), value: appState.document.isDirty)
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var lineCountText: String {
        L10n.lines(appState.document.lineCount)
    }

    private var wordCountText: String {
        L10n.words(appState.document.wordCount)
    }

    private var characterCountText: String {
        L10n.characters(appState.document.characterCount)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
    }

    private func item(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.18), value: text)
    }
}
