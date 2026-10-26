import AppKit
import SwiftUI

@main
struct IrisEditorApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appState.newDocument()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open…") {
                    appState.openDocument()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Close Tab") {
                    appState.closeTab(at: appState.currentTabIndex)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Next Tab") {
                    appState.selectTab(at: (appState.currentTabIndex + 1) % appState.tabs.count)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(appState.tabs.count < 2)

                Button("Previous Tab") {
                    let count = appState.tabs.count
                    appState.selectTab(at: (appState.currentTabIndex - 1 + count) % count)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(appState.tabs.count < 2)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    appState.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Divider()
                Button("Find & Replace…") {
                    appState.showFindReplace = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Go to Line…") {
                    appState.showGoToLine = true
                }
                .keyboardShortcut("g", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Button("Zoom In") {
                    appState.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    appState.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    appState.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Format") {
                Button("Bold") {
                    appState.toggleMarkdownFormat(prefix: "**")
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    appState.toggleMarkdownFormat(prefix: "*")
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("Inline Code") {
                    appState.toggleMarkdownFormat(prefix: "`")
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Strikethrough") {
                    appState.toggleMarkdownFormat(prefix: "~~")
                }

                Divider()

                Button("Heading") {
                    appState.toggleMarkdownFormat(prefix: "# ")
                }

                Button("Bulleted List") {
                    appState.toggleMarkdownFormat(prefix: "- ")
                }

                Button("Block Quote") {
                    appState.toggleMarkdownFormat(prefix: "> ")
                }

                Divider()

                Button("Insert Table") {
                    appState.insertSnippet(ContentView.tableTemplate)
                }

                Divider()

                Button("Toggle Preview") {
                    appState.viewMode = appState.viewMode.next
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About Iris Editor") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandMenu("Model") {
                Button("Load GPT-2 Model… (Coming Soon)") {
                    GPT2UnavailableAlert.present()
                }

                Divider()

                Button("Trigger Autocomplete") {
                    GPT2UnavailableAlert.present()
                }
                .keyboardShortcut(" ", modifiers: .control)
                .disabled(true)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.confirmDiscardAllTabs() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

@MainActor
private enum GPT2UnavailableAlert {
    static func present() {
        let alert = NSAlert()
        alert.messageText = "GPT-2 Autocomplete"
        alert.informativeText = """
        Running GPT-2 in Swift requires converting the model to Core ML. \
        This feature will be added in a future update.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
