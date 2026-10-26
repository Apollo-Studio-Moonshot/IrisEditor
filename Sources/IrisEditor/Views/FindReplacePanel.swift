import AppKit
import SwiftUI

/// Floating find / replace / go-to-line bar.
///
/// The controls live on top of a real `NSGlassEffectView`; on macOS 27 the glass is
/// created with `effectIsInteractive` so it responds to pointer interaction.
struct FindReplacePanel: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = FindPanelModel()
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case find
        case replace
        case line
    }

    var body: some View {
        VStack(spacing: 8) {
            if appState.showGoToLine {
                goToLineRow
            } else {
                findRow
                if model.showsReplaceField {
                    replaceRow
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 560)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 16, interactive: true)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .onExitCommand {
            appState.closeFindPanel()
        }
        .onAppear {
            syncFocus()
        }
        .onChange(of: appState.showGoToLine) { _, _ in
            syncFocus()
        }
        .onChange(of: model.showsReplaceField) { _, showsReplace in
            if showsReplace {
                focus = .replace
            }
        }
    }

    // MARK: - Find & replace

    private var findRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Find", text: $appState.findText)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .find)
                .onSubmit {
                    appState.performFind(forward: true)
                }

            toggleOption("Aa", isOn: $appState.findCaseSensitive, help: "Match Case")
            toggleOption("ab", isOn: $appState.findWholeWord, help: "Whole Word")

            Text(matchSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 68, alignment: .leading)

            Button {
                appState.performFind(forward: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(appState.findMatches.isEmpty)
            .help("Previous Match")

            Button {
                appState.performFind(forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(appState.findMatches.isEmpty)
            .help("Next Match")

            Button {
                model.showsReplaceField.toggle()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help(model.showsReplaceField ? "Hide Replace" : "Show Replace")

            closeButton
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Replace with", text: $appState.replaceText)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .replace)
                .onSubmit {
                    appState.replaceCurrentMatch()
                }

            Button("Replace") {
                appState.replaceCurrentMatch()
            }
            .disabled(appState.findMatchIndex < 0)

            Button("All") {
                appState.replaceAllMatches()
            }
            .disabled(appState.findMatches.isEmpty)
        }
        .padding(.leading, 24)
    }

    private var matchSummary: String {
        guard !appState.findText.isEmpty else { return "" }
        if appState.findMatches.isEmpty { return "Not found" }
        if appState.findMatchIndex >= 0 {
            return "\(appState.findMatchIndex + 1) of \(appState.findMatches.count)"
        }
        return appState.findMatches.count == 1
            ? "1 match"
            : "\(appState.findMatches.count) matches"
    }

    // MARK: - Go to line

    private var goToLineRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Line number", text: $model.lineText)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .line)
                .onSubmit(goToLine)

            Text("of \(appState.document.lineCount)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 68, alignment: .leading)

            Button("Go", action: goToLine)
                .buttonStyle(.borderedProminent)
                .disabled(lineNumber == nil)

            closeButton
        }
    }

    private func toggleOption(_ label: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isOn.wrappedValue
                              ? Color.accentColor.opacity(0.25)
                              : Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                )
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var closeButton: some View {
        Button {
            appState.closeFindPanel()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.cancelAction)
        .help("Close")
    }

    // MARK: - Actions

    private var lineNumber: Int? {
        guard let line = Int(model.lineText.trimmingCharacters(in: .whitespaces)),
              line > 0 else {
            return nil
        }
        return line
    }

    private func goToLine() {
        guard let line = lineNumber else { return }
        appState.goToLine(line)
    }

    private func syncFocus() {
        focus = appState.showGoToLine ? .line : .find
    }
}

@MainActor
final class FindPanelModel: ObservableObject {
    @Published var showsReplaceField = false
    @Published var lineText = ""
}
