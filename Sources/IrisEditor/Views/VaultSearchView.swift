import SwiftUI

/// Full-vault search overlay (⇧⌘F) with inline result previews.
struct VaultSearchView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField(L10n.searchAllNotesPlaceholder, text: $appState.vaultSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFieldFocused)
                    .onSubmit { openFirstResult() }
                    .accessibilityLabel(L10n.searchAllNotesPlaceholder)
                    .accessibilityIdentifier("VaultSearch.Field")

                if !appState.vaultSearchQuery.isEmpty {
                    Button {
                        appState.vaultSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.clearSearch)
                    .accessibilityIdentifier("VaultSearch.Clear")
                }

                Text("⇧⌘F")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Obsidian-style operators are only discoverable if they are on screen.
            Text(L10n.searchOperatorsHint)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .accessibilityIdentifier("VaultSearch.OperatorHint")

            Divider()

            if appState.vaultSearchQuery.isEmpty {
                hint(L10n.searchVaultHint)
            } else if appState.vaultSearchResults.isEmpty {
                hint(L10n.noMatches(appState.vaultSearchQuery))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(appState.vaultSearchResults) { result in
                            Button {
                                appState.open(url: result.url)
                                appState.reveal(line: result.line)
                                appState.toggleVaultSearch()
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(result.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.primary)
                                            Text("L\(result.line)")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(result.excerpt)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(result.title)
                            .accessibilityValue("L\(result.line)")
                            .accessibilityIdentifier("VaultSearch.Result.\(result.url.lastPathComponent)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 340)

                Divider()
                Text(L10n.results(appState.vaultSearchResults.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
        .frame(width: 640)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 14, interactive: true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
        .clipShape(.rect(cornerRadius: 14))
        .onAppear { isFieldFocused = true }
        .onExitCommand { appState.toggleVaultSearch() }
        .accessibilityLabel(L10n.vaultSearch)
        .accessibilityIdentifier("VaultSearch")
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openFirstResult() {
        guard let first = appState.vaultSearchResults.first else { return }
        appState.open(url: first.url)
        appState.reveal(line: first.line)
        appState.toggleVaultSearch()
    }
}
