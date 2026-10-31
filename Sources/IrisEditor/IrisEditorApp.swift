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
                Button(L10n.newTabMenu) {
                    appState.newDocument()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .newTab))

                Button(L10n.openMenu) {
                    appState.openDocument()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .openDocument))
            }

            CommandGroup(after: .newItem) {
                Button(L10n.closeTabMenu) {
                    if appState.isGraphTabActive {
                        appState.closeGraphTab()
                    } else {
                        appState.closeTab(at: appState.currentTabIndex)
                    }
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .closeTab))

                Button(L10n.reopenClosedTab) {
                    appState.reopenClosedTab()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .reopenClosedTab))
                .disabled(appState.closedFileURLs.isEmpty)

                Divider()

                Menu(L10n.openRecent) {
                    if appState.recentFiles.isEmpty {
                        Button(L10n.noRecentFiles) {}
                            .disabled(true)
                    } else {
                        ForEach(appState.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                appState.open(url: url)
                            }
                            .help(url.path)
                        }

                        Divider()

                        Button(L10n.clearMenu) {
                            appState.clearRecentFiles()
                        }
                    }
                }

                Divider()

                Button(L10n.nextTab) {
                    appState.selectNextTab()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .nextTab))
                .disabled(appState.tabs.count + (appState.isGraphTabOpen ? 1 : 0) < 2)

                Button(L10n.previousTab) {
                    appState.selectPreviousTab()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .previousTab))
                .disabled(appState.tabs.count + (appState.isGraphTabOpen ? 1 : 0) < 2)

                Divider()

                ForEach(1...9, id: \.self) { number in
                    Button(number == 9 ? L10n.lastTab : L10n.tab(number)) {
                        appState.selectTab(number: number)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                    .disabled(appState.tabs.count < (number == 9 ? 2 : number))
                }
            }

            CommandGroup(replacing: .printItem) {
                Button(L10n.printDocument) {
                    appState.printDocument()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .printDocument))
            }

            CommandMenu(L10n.navigateMenu) {
                Button(L10n.quickSwitcher) {
                    appState.toggleQuickSwitcher()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .quickSwitcher))

                Button(L10n.commandPalette) {
                    appState.toggleCommandPalette()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .commandPalette))

                Divider()

                Button(L10n.toggleOutline) {
                    appState.toggleOutline()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .toggleOutline))

                Button(L10n.zenMode) {
                    appState.toggleZenMode()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .zenMode))

                Button(L10n.versionHistory) {
                    appState.presentVersionHistory()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .versionHistory))
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button(L10n.pasteAsMarkdown) {
                    appState.pasteAsMarkdown()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .pasteAsMarkdown))
            }

            CommandGroup(replacing: .saveItem) {
                Button(L10n.saveMenu) {
                    appState.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(L10n.saveAsMenu) {
                    appState.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button(L10n.exportHTML) {
                    appState.exportHTML()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .exportHTML))

                Button(L10n.exportPDF) {
                    appState.exportPDF()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .exportPDF))

                Button(L10n.exportRTF) {
                    appState.exportRTF()
                }
            }

            CommandGroup(after: .textEditing) {
                Divider()
                Button(L10n.findReplace) {
                    appState.showFindReplace = true
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .findReplace))

                Button(L10n.goToLine) {
                    appState.showGoToLine = true
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .goToLine))
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Button(L10n.zoomIn) {
                    appState.zoomIn()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .zoomIn))

                Button(L10n.zoomOut) {
                    appState.zoomOut()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .zoomOut))

                Button(L10n.actualSize) {
                    appState.resetZoom()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .actualSize))
            }

            CommandMenu(L10n.formatMenu) {
                Button(L10n.bold) {
                    appState.toggleMarkdownFormat(prefix: "**")
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .bold))

                Button(L10n.italic) {
                    appState.toggleMarkdownFormat(prefix: "*")
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .italic))

                Divider()

                Button(L10n.inlineCode) {
                    appState.toggleMarkdownFormat(prefix: "`")
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .inlineCode))

                Button(L10n.strikethrough) {
                    appState.toggleMarkdownFormat(prefix: "~~")
                }

                Divider()

                Button(L10n.heading) {
                    appState.toggleMarkdownFormat(prefix: "# ")
                }

                Button(L10n.bulletedList) {
                    appState.toggleMarkdownFormat(prefix: "- ")
                }

                Button(L10n.blockQuote) {
                    appState.toggleMarkdownFormat(prefix: "> ")
                }

                Divider()

                Button(L10n.insertTable) {
                    appState.insertSnippet(ContentView.tableTemplate)
                }

                Divider()

                Button(L10n.togglePreview) {
                    appState.viewMode = appState.viewMode.next
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .togglePreview))
            }

            CommandGroup(replacing: .appInfo) {
                Button(L10n.aboutIris) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandMenu(L10n.aiMenu) {
                Button(L10n.inlineCompletion) {
                    appState.requestInlineCompletion()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .inlineCompletion))

                Button(L10n.rewriteSelection) {
                    appState.requestRewriteSelection()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .rewriteSelection))

                Divider()

                Button(L10n.summarizeDocument) {
                    appState.summarizeDocument()
                }

                Button(L10n.generateTitleTags) {
                    appState.generateTitleAndTags()
                }

                Divider()

                Text(appState.ai.availabilityDescription)
                    .disabled(true)
            }

            CommandMenu(L10n.pluginsMenu) {
                if appState.pluginCommands.isEmpty {
                    Text(L10n.noPlugins)
                        .disabled(true)
                } else {
                    ForEach(appState.pluginCommands) { command in
                        Button(command.title) {
                            appState.runPluginCommand(command)
                        }
                        .irisKeyboardShortcut(command.shortcut.flatMap { KeybindingParser.shortcut(from: $0) })
                    }
                }

                if !appState.pluginExporters.isEmpty {
                    Divider()
                    Menu("Export with Plugin") {
                        ForEach(appState.pluginExporters) { exporter in
                            Button("\(exporter.title) — \(exporter.pluginName)") {
                                appState.exportWithPlugin(exporter)
                            }
                        }
                    }
                }

                Divider()

                Button(L10n.reloadPlugins) {
                    appState.reloadPlugins()
                }

                Button(L10n.openPluginsFolder) {
                    appState.openPluginsFolder()
                }

                Button(L10n.installSamplePlugin) {
                    appState.installSamplePlugin()
                }
            }

            CommandMenu(L10n.vaultMenu) {
                Button(L10n.newNoteMenu) {
                    appState.createNote()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .newNote))

                Button(L10n.searchAllNotes) {
                    appState.toggleVaultSearch()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .vaultSearch))

                Button(L10n.dailyNote) {
                    appState.openDailyNote()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .dailyNote))

                Divider()

                Button(appState.isCurrentNoteStarred ? L10n.unstarNote : L10n.starNote) {
                    appState.toggleStarForCurrentNote()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .toggleStar))

                Button(L10n.openGraphWindow) {
                    appState.openGraphTab()
                }
                .irisKeyboardShortcut(appState.keyboardShortcut(for: .openGraphWindow))

                Button(L10n.searchNotes) {
                    appState.setSidebarPane(.files)
                    appState.sidebarSearchQuery = ""
                    NotificationCenter.default.post(name: .focusSidebarSearch, object: nil)
                }

                Divider()

                Menu(L10n.sidebarMenu) {
                    ForEach(VaultPane.allCases) { pane in
                        Button(pane.title) {
                            appState.setSidebarPane(pane)
                        }
                    }
                }

                Menu(L10n.insertTemplate) {
                    if appState.vaultTemplates.isEmpty {
                        Text(L10n.noTemplates)
                            .disabled(true)
                    } else {
                        ForEach(appState.vaultTemplates, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                appState.applyTemplate(url)
                            }
                        }
                    }
                }

                Divider()

                Button(L10n.chooseVaultFolderMenu) {
                    appState.chooseVaultFolder()
                }

                Button(L10n.versionHistory) {
                    appState.presentVersionHistory()
                }

                Button(L10n.openCurrentNoteToSide) {
                    appState.openInSecondPane()
                }
                .disabled(appState.secondDocument != nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        MenuBarExtra("Iris Capture", systemImage: "square.and.pencil") {
            QuickCaptureView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Advertise the “Open Markdown in Iris” service declared in Info.plist.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Services entry point for `NSServices` in Info.plist. Receives either file URLs
    /// (Finder/Open With) or a plain-text selection from any app.
    @objc func openMarkdown(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        AppState.shared.openServicePasteboard(pasteboard)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.saveSession()
        return AppState.shared.confirmDiscardAllTabs() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.saveSession()
        // A clean quit means every dirty document was already saved or explicitly
        // discarded, so no crash-recovery drafts should remain. Clearing them also
        // removes drafts left behind by older builds that leaked discarded work.
        DraftStore.clear()
        SpotlightIndexer.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "iriseditor" {
                AppState.shared.handleCaptureURL(url)
            } else {
                AppState.shared.open(urls: [url])
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

private extension View {
    /// Applies a shortcut only when one is available, so a missing binding leaves the
    /// menu item without a key equivalent instead of crashing the command builder.
    @ViewBuilder
    func irisKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
