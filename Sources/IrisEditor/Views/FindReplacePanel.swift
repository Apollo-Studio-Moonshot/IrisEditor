import SwiftUI

struct FindReplacePanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var showReplace = false
    @State private var goToLineInput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Find/Replace or Go To Line selector
            Picker("", selection: $showReplace) {
                Text("Find").tag(false)
                Text("Replace").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            if appState.showGoToLine {
                goToLineSection
            } else {
                findSection
                if showReplace {
                    replaceSection
                }
            }
        }
        .padding(.bottom, 12)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        )
        .padding(.top, 60)
        .onDisappear {
            NotificationCenter.default.post(
                name: .findHighlight,
                object: nil,
                userInfo: ["ranges": []]
            )
        }
    }
    
    private var findSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            
            TextField("Find", text: $appState.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            Text("\(appState.findMatches.count) matches")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            
            Button {
                appState.performFind(forward: false)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.glass)
            
            Button {
                appState.performFind(forward: true)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.glass)
            
            Button {
                appState.showFindReplace = false
                appState.showGoToLine = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private var replaceSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            
            TextField("Replace with", text: $appState.replaceText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            Button("Replace") {
                appState.replaceCurrent()
            }
            .buttonStyle(.glass)
            .font(.system(size: 12, weight: .medium))
            
            Button("All") {
                appState.replaceAll()
            }
            .buttonStyle(.glass)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var goToLineSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            
            TextField("Go to line number", text: $goToLineInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            Button("Go") {
                if let line = Int(goToLineInput), line > 0 {
                    appState.goToLine(line)
                    appState.showGoToLine = false
                }
            }
            .buttonStyle(.glassProminent)
            .font(.system(size: 12, weight: .semibold))
            
            Button {
                appState.showGoToLine = false
                appState.showFindReplace = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
