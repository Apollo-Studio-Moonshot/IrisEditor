import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ZStack {
            // Animated gradient background for Liquid Glass effect
            BackgroundGradient()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ToolbarBar()
                    .background(.regularMaterial)
                
                EditorContainer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                StatusBarView()
                    .background(.thinMaterial)
                    .frame(height: 28)
            }
            
            // Floating Find/Replace / Go-to-Line Panel
            if appState.showFindReplace || appState.showGoToLine {
                FindReplacePanel()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }
}

// MARK: - Background

struct BackgroundGradient: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.18, blue: 0.25),
                    Color(red: 0.10, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated orbs for depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 400
                    )
                )
                .frame(width: 600, height: 600)
                .offset(x: animate ? 150 : -150, y: animate ? -100 : 100)
                .blur(radius: 40)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animate)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 350
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: animate ? -120 : 120, y: animate ? 80 : -80)
                .blur(radius: 40)
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animate)
        }
        .onAppear { animate = true }
    }
}
