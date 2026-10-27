import SwiftUI

/// Floating glass strip showing wiki-link completions while typing `[[`.
struct WikiSuggestionBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 9)

            ForEach(Array(appState.wikiSuggestions.enumerated()), id: \.offset) { index, name in
                Button {
                    NotificationCenter.default.post(
                        name: .wikiAutocompleteAccept,
                        object: nil,
                        userInfo: ["target": name]
                    )
                } label: {
                    Text(name)
                        .font(.system(size: 11, weight: index == appState.wikiSuggestionIndex ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(index == appState.wikiSuggestionIndex
                                      ? Color.accentColor.opacity(0.18)
                                      : Color.clear)
                        }
                        .foregroundStyle(index == appState.wikiSuggestionIndex
                                         ? Color.accentColor
                                         : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityValue(index == appState.wikiSuggestionIndex ? L10n.selected : "")
                .accessibilityIdentifier("WikiSuggestion.\(name)")

                if index < appState.wikiSuggestions.count - 1 {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Text("↹")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 9)
        }
        .padding(.vertical, 5)
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 10, interactive: true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.wikiSuggestions)
        .accessibilityIdentifier("WikiSuggestionBar")
    }
}
