import AppKit
import SwiftUI

/// Obsidian-style command palette: a floating search box that filters editor commands
/// and executes them on selection.
struct CommandPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @StateObject private var model = CommandPaletteModel()
    @FocusState private var isFocused: Bool

    private struct PaletteCommand: Identifiable {
        var id: String { title }
        let title: String
        let icon: String
        let shortcut: String?
        let action: () -> Void
    }

    private var commands: [PaletteCommand] {
        [
            PaletteCommand(title: "New Tab", icon: "plus.square", shortcut: "⌘T") {
                appState.newDocument()
            },
            PaletteCommand(title: "Close Tab", icon: "xmark.square", shortcut: "⌘W") {
                appState.closeTab(at: appState.currentTabIndex)
            },
            PaletteCommand(title: "Reopen Closed Tab", icon: "arrow.uturn.backward.square", shortcut: "⇧⌘T") {
                appState.reopenClosedTab()
            },
            PaletteCommand(title: "Open File…", icon: "folder", shortcut: "⌘O") {
                appState.openDocument()
            },
            PaletteCommand(title: "Quick Switcher…", icon: "rectangle.stack", shortcut: "⌘P") {
                appState.showQuickSwitcher = true
            },
            PaletteCommand(title: "Save", icon: "square.and.arrow.down", shortcut: "⌘S") {
                _ = appState.saveDocument()
            },
            PaletteCommand(title: "Save As…", icon: "square.and.arrow.down.on.square", shortcut: "⇧⌘S") {
                _ = appState.saveDocumentAs()
            },
            PaletteCommand(title: "Find & Replace", icon: "magnifyingglass", shortcut: "⌘F") {
                appState.showFindReplace = true
            },
            PaletteCommand(title: "Go to Line", icon: "arrow.up.arrow.down", shortcut: "⌘G") {
                appState.showGoToLine = true
            },
            PaletteCommand(title: "Toggle Outline", icon: "list.bullet.indent", shortcut: "⇧⌘O") {
                appState.toggleOutline()
            },
            PaletteCommand(title: "View: Source", icon: "doc.richtext", shortcut: nil) {
                appState.viewMode = .source
            },
            PaletteCommand(title: "View: Split", icon: "rectangle.split.2x1", shortcut: nil) {
                appState.viewMode = .split
            },
            PaletteCommand(title: "View: Preview", icon: "text.alignleft", shortcut: "⌥⌘P") {
                appState.viewMode = .preview
            },
            PaletteCommand(title: "Bold", icon: "bold", shortcut: "⌘B") {
                appState.toggleMarkdownFormat(prefix: "**")
            },
            PaletteCommand(title: "Italic", icon: "italic", shortcut: "⌘I") {
                appState.toggleMarkdownFormat(prefix: "*")
            },
            PaletteCommand(title: "Inline Code", icon: "chevron.left.forwardslash.chevron.right", shortcut: "⌘K") {
                appState.toggleMarkdownFormat(prefix: "`")
            },
            PaletteCommand(title: "Strikethrough", icon: "strikethrough", shortcut: nil) {
                appState.toggleMarkdownFormat(prefix: "~~")
            },
            PaletteCommand(title: "Heading 1", icon: "textformat.size.larger", shortcut: nil) {
                appState.toggleMarkdownFormat(prefix: "# ")
            },
            PaletteCommand(title: "Bulleted List", icon: "list.bullet", shortcut: nil) {
                appState.toggleMarkdownFormat(prefix: "- ")
            },
            PaletteCommand(title: "Block Quote", icon: "text.quote", shortcut: nil) {
                appState.toggleMarkdownFormat(prefix: "> ")
            },
            PaletteCommand(title: "Insert Table", icon: "tablecells", shortcut: nil) {
                appState.insertSnippet(ContentView.tableTemplate)
            },
            PaletteCommand(title: "Zoom In", icon: "plus.magnifyingglass", shortcut: "⌘=") {
                appState.zoomIn()
            },
            PaletteCommand(title: "Zoom Out", icon: "minus.magnifyingglass", shortcut: "⌘-") {
                appState.zoomOut()
            },
            PaletteCommand(title: "Reset Zoom", icon: "equal.square", shortcut: "⌘0") {
                appState.resetZoom()
            },
            PaletteCommand(title: "Settings…", icon: "gearshape", shortcut: "⌘,") {
                openSettings()
            },
        ]
    }

    private var filteredCommands: [PaletteCommand] {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return commands }

        return commands
            .compactMap { command -> (PaletteCommand, Double)? in
                guard let score = FuzzyMatch.score(query: query, candidate: command.title) else {
                    return nil
                }
                return (command, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            if filteredCommands.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                commandRow(command, index: index)
                                    .id(command.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: model.selectionIndex) { _, newValue in
                        let safeIndex = max(0, min(newValue, filteredCommands.count - 1))
                        guard filteredCommands.indices.contains(safeIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(filteredCommands[safeIndex].id, anchor: .center)
                        }
                    }
                }
            }

            footer
        }
        .frame(width: 500)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .onAppear {
            model.reset()
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: model.searchText) { _, _ in
            model.selectionIndex = 0
        }
        .onExitCommand {
            appState.dismissCommandPalette()
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Type a command…", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit {
                    executeSelected()
                }
                .onKeyPress { press in
                    switch press.key {
                    case .upArrow:
                        model.moveSelection(-1, count: filteredCommands.count)
                        return .handled
                    case .downArrow:
                        model.moveSelection(1, count: filteredCommands.count)
                        return .handled
                    case .tab:
                        model.moveSelection(press.modifiers.contains(.shift) ? -1 : 1, count: filteredCommands.count)
                        return .handled
                    default:
                        return .ignored
                    }
                }

            Button {
                appState.dismissCommandPalette()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("↑↓ navigate")
            Text("↩ run")
            Text("esc close")
            Spacer()
            Text("\(filteredCommands.count) commands")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
    }

    // MARK: - Command row

    private func commandRow(_ command: PaletteCommand, index: Int) -> some View {
        let isSelected = index == min(model.selectionIndex, filteredCommands.count - 1)

        return Button {
            execute(command)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: command.icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(command.title)
                    .font(.system(size: 13))

                Spacer()

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func executeSelected() {
        let safeIndex = min(model.selectionIndex, filteredCommands.count - 1)
        guard filteredCommands.indices.contains(safeIndex) else { return }
        execute(filteredCommands[safeIndex])
    }

    private func execute(_ command: PaletteCommand) {
        // Dismiss first, then execute the command on the next run-loop tick so the
        // overlay is removed before any UI-altering action runs.
        appState.dismissCommandPalette()
        DispatchQueue.main.async {
            command.action()
        }
    }
}

@MainActor
final class CommandPaletteModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectionIndex = 0

    func reset() {
        searchText = ""
        selectionIndex = 0
    }

    func moveSelection(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selectionIndex = ((selectionIndex + delta) % count + count) % count
    }
}
