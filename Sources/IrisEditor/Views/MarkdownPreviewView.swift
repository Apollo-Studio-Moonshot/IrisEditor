import AppKit
import SwiftUI

/// Renders the current Markdown document as rich text using `AttributedString(markdown:)`.
///
/// This is a lightweight read-only preview built entirely on `Foundation`'s Markdown
/// support — no third-party renderer or web view is required.
struct MarkdownPreviewView: View {
    let markdown: String

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    var body: some View {
        ScrollView {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background {
            GlassBackdrop(style: .regular, cornerRadius: 0)
                .ignoresSafeArea()
        }
    }
}
