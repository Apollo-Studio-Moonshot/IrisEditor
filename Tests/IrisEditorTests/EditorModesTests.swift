import Foundation
import Testing
@testable import IrisEditor

struct VimEngineTests {
    private func press(_ key: Character, on engine: inout VimEngine, text: String, selection: NSRange) -> VimResult {
        engine.handle(key: .character(key), text: text, selection: selection)
    }

    @Test func movesAndEntersInsertMode() {
        var engine = VimEngine()
        var result = press("l", on: &engine, text: "abc\ndef", selection: NSRange(location: 0, length: 0))
        #expect(result.selection.location == 1)
        #expect(result.mode == .normal)

        result = press("i", on: &engine, text: "abc\ndef", selection: result.selection)
        #expect(result.mode == .insert)
        #expect(result.selection.location == 1)

        result = engine.exitInsertMode(text: "abc\ndef", selection: NSRange(location: 3, length: 0))
        #expect(result.mode == .normal)
        #expect(result.selection.location == 2)
    }

    @Test func countsRepeatMotionsAndDeletes() {
        var engine = VimEngine()
        let text = "abcdef"
        _ = press("2", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        let moved = press("l", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        #expect(moved.selection.location == 2)

        _ = press("2", on: &engine, text: text, selection: moved.selection)
        let deleted = press("x", on: &engine, text: text, selection: moved.selection)
        #expect(deleted.text == "abef")
        #expect(deleted.selection.location == 2)
    }

    @Test func ddDeletesTheCurrentLine() {
        var engine = VimEngine()
        let text = "one\ntwo\nthree"
        _ = press("d", on: &engine, text: text, selection: NSRange(location: 4, length: 0))
        let result = press("d", on: &engine, text: text, selection: NSRange(location: 4, length: 0))
        #expect(result.text == "one\nthree")
        #expect(result.selection.location == 4)
    }

    @Test func countAppliesToLineOperators() {
        var engine = VimEngine()
        let text = "one\ntwo\nthree\nfour"
        _ = press("3", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        _ = press("d", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        let result = press("d", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        #expect(result.text == "four")
    }

    @Test func yyPastesLinewise() {
        var engine = VimEngine()
        let text = "abc"
        _ = press("y", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        let yanked = press("y", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        #expect(yanked.text == text)

        let pasted = press("p", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        #expect(pasted.text == "abcabc")
    }

    @Test func visualSelectionDeletes() {
        var engine = VimEngine()
        let text = "abcdef"
        let visual = press("v", on: &engine, text: text, selection: NSRange(location: 1, length: 0))
        #expect(visual.mode == .visual)
        let moved = press("l", on: &engine, text: text, selection: visual.selection)
        #expect(moved.selection == NSRange(location: 1, length: 2))
        let deleted = press("d", on: &engine, text: text, selection: moved.selection)
        #expect(deleted.text == "adef")
        #expect(deleted.mode == .normal)
    }

    @Test func openLineBelowPlacesCaretOnTheNewLine() {
        var engine = VimEngine()
        let result = press("o", on: &engine, text: "abc", selection: NSRange(location: 1, length: 0))
        #expect(result.text == "abc\n")
        #expect(result.mode == .insert)
        #expect(result.selection.location == 4)

        var middle = VimEngine()
        let inserted = press("o", on: &middle, text: "abc\ndef", selection: NSRange(location: 1, length: 0))
        #expect(inserted.text == "abc\n\ndef")
        #expect(inserted.selection.location == 4)
    }

    @Test func xDoesNotJoinTheNextLine() {
        var engine = VimEngine()
        let text = "ab\ncd"
        let atEnd = press("x", on: &engine, text: text, selection: NSRange(location: 2, length: 0))
        #expect(atEnd.text == text)
    }

    @Test func commandModeSavesAndJumps() {
        var engine = VimEngine()
        let text = "a\nb\nc"
        _ = press(":", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        _ = press("w", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        let saved = engine.handle(key: .returnKey, text: text, selection: NSRange(location: 0, length: 0))
        #expect(saved.command == .save)
        #expect(saved.mode == .normal)

        _ = press(":", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        _ = press("3", on: &engine, text: text, selection: NSRange(location: 0, length: 0))
        let jumped = engine.handle(key: .returnKey, text: text, selection: NSRange(location: 0, length: 0))
        #expect(jumped.selection.location == 4)
    }
}

struct AppearanceSettingsTests {
    @Test func decodesNewThemeAndKeymapSettings() throws {
        let json = """
        {"appearance":"highContrast","accent":"custom","accentHex":"#112233","editingMode":"vim"}
        """
        let settings = try JSONDecoder().decode(EditorSettings.self, from: Data(json.utf8))
        #expect(settings.appearance == .highContrast)
        #expect(settings.appearance.isHighContrast)
        #expect(settings.accent == .custom)
        #expect(settings.accentHex == "#112233")
        #expect(settings.editingMode == .vim)
        #expect(AccentTheme.color(fromHex: settings.accentHex) != nil)
    }

    @Test func missingSettingsFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(EditorSettings.self, from: Data("{}".utf8))
        #expect(settings.appearance == .system)
        #expect(settings.editingMode == .standard)
        #expect(settings.appearance.colorScheme == nil)
    }
}

struct PrintExportTests {
    @Test func exportedHTMLCarriesPrintPageRules() {
        let html = MarkdownHTMLExport.document(from: "# Title", title: "Title")
        #expect(html.contains("@media print"))
        #expect(html.contains("@page"))
    }
}

struct PluginHostTests {
    @Test @MainActor func loadsAndExecutesJavaScriptPlugin() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let manifest = #"{"id":"test-plugin","name":"Test Plugin","main":"main.js"}"#
        let script = #"""
        iris.registerCommand({ id: "greet", title: "Greet" }, function (ctx) {
          ctx.insertText("hello " + ctx.documentName);
        });
        iris.registerExporter({ id: "raw", title: "Raw", extension: "html" }, function (doc) {
          return "<html>" + doc.markdown + "</html>";
        });
        """#
        try manifest.write(to: folder.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try script.write(to: folder.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)

        let host = PluginHost()
        let loaded = host.loadPlugins(in: [folder], disabledIDs: [])
        #expect(loaded.errors.isEmpty)
        #expect(loaded.plugins.count == 1)
        #expect(loaded.plugins.first?.commands.count == 1)
        #expect(loaded.plugins.first?.exporters.count == 1)

        guard let command = loaded.plugins.first?.commands.first else { return }
        var inserted = ""
        let context = PluginCommandContext(
            text: "body",
            selection: NSRange(location: 0, length: 0),
            documentName: "Demo.md",
            filePath: nil,
            insertText: { inserted = $0 },
            replaceSelection: { _ in },
            setText: { _ in },
            setSelection: { _, _ in },
            save: {},
            alert: { _, _ in },
            setAccent: { _ in },
            setPreviewTheme: { _ in },
            setAppearance: { _ in }
        )
        host.execute(commandID: command.id, context: context)
        #expect(host.lastError == nil)
        #expect(inserted == "hello Demo.md")

        guard let exporter = loaded.plugins.first?.exporters.first else { return }
        let html = host.exportHTML(
            exporterID: exporter.id,
            markdown: "# Hi",
            title: "Demo",
            theme: .system
        )
        #expect(html == "<html># Hi</html>")
    }
}

struct PluginNamingTests {
    @Test func namespacesAndSanitizesIDs() {
        #expect(PluginHost.sanitizedID("Hello World!") == "hello-world")
        #expect(PluginHost.sanitizedID("  ") == "plugin")
        #expect(PluginHost.sanitizedID("a__b") == "a__b")
    }

    @Test func decodesManifestDescriptions() throws {
        let json = """
        {"id":"demo","name":"Demo","description":"A demo","main":"index.js"}
        """
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        #expect(manifest.id == "demo")
        #expect(manifest.summary == "A demo")
        #expect(manifest.main == "index.js")
    }
}
