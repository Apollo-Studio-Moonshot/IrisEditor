import AppKit
import SwiftUI

/// Obsidian-style quick switcher: fuzzy-search open tabs and recently opened files,
/// then jump straight to a note.
struct QuickSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = QuickSwitcherModel()
    @FocusState private var isFocused: Bool

    private struct SwitchEntry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let isOpen: Bool
        let action: () -> Void

        var searchableText: String {
            "\(title) \(subtitle)"
        }
    }

    private var entries: [SwitchEntry] {
        let openURLs = Set(appState.tabs.compactMap { $0.fileURL?.standardizedFileURL })

        var result: [SwitchEntry] = appState.tabs.enumerated().map { index, tab in
            SwitchEntry(
                id: "tab-\(tab.id.uuidString)",
                title: tab.displayName,
                subtitle: tab.fileURL?
                    .deletingLastPathComponent()
                    .path
                    .replacingOccurrences(
                        of: NSHomeDirectory(),
                        with: "~"
                    ) ?? "Unsaved note",
                icon: tab.isDirty ? "doc.badge.ellipsis" : "doc.text",
                isOpen: true
            ) {
                appState.selectTab(at: index)
            }
        }

        for url in appState.recentFiles where !openURLs.contains(url.standardizedFileURL) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            result.append(
                SwitchEntry(
                    id: "recent-\(url.path)",
                    title: url.lastPathComponent,
                    subtitle: url.deletingLastPathComponent().path
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                    icon: "clock",
                    isOpen: false
                ) {
                    appState.open(url: url)
                }
            )
        }

        return result
    }

    private var filteredEntries: [SwitchEntry] {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        return entries
            .compactMap { entry -> (SwitchEntry, Double)? in
                let titleScore = FuzzyMatch.score(query: query, candidate: entry.title)
                let pathScore = FuzzyMatch.score(query: query, candidate: entry.searchableText)
                    .map { $0 * 0.6 }
                guard let score = [titleScore, pathScore].compactMap({ $0 }).max() else {
                    return nil
                }
                return (entry, score + (entry.isOpen ? 0.5 : 0))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.quaternary)
                    Text(model.query.isEmpty ? "No open or recent notes" : "No matching notes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Use ⌘O to open a file from disk.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                row(entry, index: index)
                                    .id(entry.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: model.selectionIndex) { _, newValue in
                        let safeIndex = max(0, min(newValue, filteredEntries.count - 1))
                        guard filteredEntries.indices.contains(safeIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(filteredEntries[safeIndex].id, anchor: .center)
                        }
                    }
                }
            }

            footer
        }
        .frame(width: 560)
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
            model.reset(initialQuery: appState.consumeQuickSwitcherInitialQuery())
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: model.query) { _, _ in
            model.selectionIndex = 0
        }
        .onExitCommand {
            appState.dismissQuickSwitcher()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Go to note…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit {
                    executeSelected()
                }
                .onKeyPress { press in
                    switch press.key {
                    case .upArrow:
                        model.moveSelection(-1, count: filteredEntries.count)
                        return .handled
                    case .downArrow:
                        model.moveSelection(1, count: filteredEntries.count)
                        return .handled
                    case .tab:
                        model.moveSelection(press.modifiers.contains(.shift) ? -1 : 1, count: filteredEntries.count)
                        return .handled
                    default:
                        return .ignored
                    }
                }

            Button {
                appState.dismissQuickSwitcher()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func row(_ entry: SwitchEntry, index: Int) -> some View {
        let isSelected = index == min(model.selectionIndex, filteredEntries.count - 1)

        return Button {
            execute(entry)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: entry.icon)
                    .frame(width: 18)
                    .foregroundStyle(entry.isOpen ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(entry.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if entry.isOpen {
                    Text("OPEN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
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

    private var footer: some View {
        HStack(spacing: 10) {
            Text("↑↓ navigate")
            Text("↩ open")
            Text("esc close")
            Spacer()
            Text("\(filteredEntries.count) notes")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
    }

    private func executeSelected() {
        let safeIndex = min(model.selectionIndex, filteredEntries.count - 1)
        guard filteredEntries.indices.contains(safeIndex) else { return }
        execute(filteredEntries[safeIndex])
    }

    private func execute(_ entry: SwitchEntry) {
        appState.dismissQuickSwitcher()
        DispatchQueue.main.async {
            entry.action()
        }
    }
}

@MainActor
final class QuickSwitcherModel: ObservableObject {
    @Published var query = ""
    @Published var selectionIndex = 0

    func reset(initialQuery: String = "") {
        query = initialQuery
        selectionIndex = 0
    }

    func moveSelection(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selectionIndex = ((selectionIndex + delta) % count + count) % count
    }
}
