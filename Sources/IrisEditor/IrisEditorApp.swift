import SwiftUI
import AppKit

@main
struct IrisEditorApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup("Iris Editor") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 500)
                .onChange(of: appState.showSettings) { oldValue, newValue in
                    if newValue {
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                        appState.showSettings = false
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { appState.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { appState.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { appState.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Open…") { appState.openDocument() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Find…") { appState.showFindReplace = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Go to Line…") { appState.showGoToLine = true }
                    .keyboardShortcut("g", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Iris Editor") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(before: .appSettings) {
                Menu("Model") {
                    Button("Load GPT-2 Model… (Coming Soon)") {
                        let alert = NSAlert()
                        alert.messageText = "GPT-2 Autocomplete"
                        alert.informativeText = "Swift cannot directly run Python's transformers/torch libraries. GPT-2 autocomplete would require converting the model to CoreML format. This feature will be added in a future update."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    .disabled(true)
                    
                    Divider()
                    
                    Button("Trigger Autocomplete (Ctrl+Space)") {
                        // Future: trigger GPT-2 suggestion
                    }
                    .keyboardShortcut(" ", modifiers: [.control])
                    .disabled(true)
                }
            }
        }
        
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
