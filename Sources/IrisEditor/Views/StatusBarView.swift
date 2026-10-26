import SwiftUI

/// Native status bar that sits below the editor and reads from the shared app state.
struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            item("Ln \(appState.cursorLine), Col \(appState.cursorColumn)")
            separator
            item(lineCountText)
            separator
            item(wordCountText)
            separator
            item(characterCountText)

            Spacer(minLength: 12)

            if appState.document.isDirty {
                item("Edited")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                separator
                    .transition(.opacity)
            }
            item(appState.document.fileSizeDescription)
            separator
            item("UTF-8")
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
        let count = appState.document.lineCount
        return count == 1 ? "1 line" : "\(count) lines"
    }

    private var wordCountText: String {
        let count = appState.document.wordCount
        return count == 1 ? "1 word" : "\(count) words"
    }

    private var characterCountText: String {
        let count = appState.document.characterCount
        return count == 1 ? "1 character" : "\(count) characters"
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
