import SwiftUI
import AppKit

// MARK: - Toolbar

struct ToolbarBar: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            // Window traffic light spacer
            Color.clear.frame(width: 70)
            
            // Document title
            VStack(alignment: .leading, spacing: 0) {
                Text(appState.document.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if appState.document.isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            
            Spacer()
            
            // File operations
            HStack(spacing: 6) {
                ToolbarButton(icon: "doc", title: "New") { appState.newDocument() }
                ToolbarButton(icon: "folder", title: "Open") { appState.openDocument() }
                ToolbarButton(icon: "square.and.arrow.down", title: "Save") { appState.saveDocument() }
            }
            
            Divider()
                .frame(height: 20)
                .overlay(.white.opacity(0.2))
            
            // Edit operations
            HStack(spacing: 6) {
                ToolbarButton(icon: "doc.text.magnifyingglass", title: "Find") {
                    appState.showFindReplace.toggle()
                }
                ToolbarButton(icon: "arrow.up.arrow.down", title: "Go to Line") {
                    appState.showGoToLine.toggle()
                }
            }
            
            Spacer()
            
            // Settings
            ToolbarButton(icon: "gearshape", title: "Settings") {
                appState.showSettings = true
            }
            
            Color.clear.frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 44)
    }
}

struct ToolbarButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }
}
