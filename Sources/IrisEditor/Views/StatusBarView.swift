import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            // Document info
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.document.isDirty ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(appState.document.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .frame(height: 14)
                .overlay(.white.opacity(0.15))
            
            // Line/Column (placeholder - actual values come from editor)
            StatusItem(icon: "text.cursor", value: "Ln \(appState.document.lineCount)")
            
            Divider()
                .frame(height: 14)
                .overlay(.white.opacity(0.15))
            
            // Word count
            StatusItem(icon: "character.book.closed", value: "\(appState.document.wordCount) words")
            
            Divider()
                .frame(height: 14)
                .overlay(.white.opacity(0.15))
            
            // Character count
            StatusItem(icon: "info", value: "\(appState.document.characterCount) chars")
            
            Spacer()
            
            // File size
            StatusItem(icon: "externaldrive", value: appState.document.fileSizeDescription)
            
            // Encoding
            StatusItem(icon: "doc.plaintext", value: "UTF-8")
        }
        .padding(.horizontal, 14)
    }
}

struct StatusItem: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
