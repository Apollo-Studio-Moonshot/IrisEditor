import Foundation
import JavaScriptCore

/// `plugin.json` shipped inside a plugin folder. Every field is optional so a single
/// `.js` file with a sensible filename can be dropped in without ceremony.
struct PluginManifest: Decodable, Equatable {
    var id: String?
    var name: String?
    var version: String?
    var author: String?
    var summary: String?
    var main: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, version, author, summary, main
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
            ?? container.decodeIfPresent(String.self, forKey: .description)
        main = try container.decodeIfPresent(String.self, forKey: .main)
    }
}

/// A command contributed by a plugin. Its `id` is namespaced with the plugin id so two
/// plugins cannot collide.
struct PluginCommandDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let shortcut: String?
    let pluginID: String
    let pluginName: String
}

/// An HTML exporter contributed by a plugin.
struct PluginExporterDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fileExtension: String
    let pluginID: String
    let pluginName: String
}

/// Metadata and contributions for one installed plugin, shown in Settings.
struct InstalledPlugin: Identifiable, Equatable {
    let id: String
    let name: String
    let version: String
    let author: String
    let summary: String
    let folderURL: URL
    let isEnabled: Bool
    let commands: [PluginCommandDescriptor]
    let exporters: [PluginExporterDescriptor]
}

/// Native capabilities exposed to a plugin command as its `ctx` argument. Every closure
/// runs on the main actor, so plugins cannot touch AppKit off the UI thread.
struct PluginCommandContext {
    let text: String
    let selection: NSRange
    let documentName: String
    let filePath: String?
    let insertText: (String) -> Void
    let replaceSelection: (String) -> Void
    let setText: (String) -> Void
    let setSelection: (Int, Int) -> Void
    let save: () -> Void
    let alert: (String, String) -> Void
    let setAccent: (String) -> Void
    let setPreviewTheme: (String) -> Void
    let setAppearance: (String) -> Void
}

enum PluginError: LocalizedError {
    case missingScript(String)
    case invalidScript(String)
    case escapedPluginFolder

    var errorDescription: String? {
        switch self {
        case .missingScript(let path):
            return "The plugin entry script was not found at \(path)."
        case .invalidScript(let message):
            return "The plugin script raised an error: \(message)"
        case .escapedPluginFolder:
            return "The plugin entry script points outside the plugin folder."
        }
    }
}

/// Loads sandboxed JavaScript plugins and executes their commands/exporters.
///
/// Plugins live in `~/Library/Application Support/IrisEditor/Plugins`. A plugin is either
/// a folder containing `plugin.json` + a JavaScript entry file, or a standalone `.js`
/// file. JavaScriptCore gives plugins no filesystem or network access; the only ways to
/// affect the app are the native functions exposed on `iris` and `ctx`.
@MainActor
final class PluginHost {
    static let shared = PluginHost()

    private var contexts: [String: JSContext] = [:]
    private var commandHandlers: [String: JSValue] = [:]
    private var exporterHandlers: [String: JSValue] = [:]

    /// Ids claimed by the plugins loaded in this pass, used to keep equal manifest ids apart.
    private var loadedIDs: Set<String> = []

    private(set) var lastError: String?

    init() {}

    var pluginsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = base
            .appendingPathComponent("IrisEditor", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var bundledPluginsDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Plugins", isDirectory: true)
    }

    /// Clears all previous registrations and rescans the user and bundled plugin folders.
    func loadPlugins(disabledIDs: Set<String>) -> (plugins: [InstalledPlugin], errors: [String]) {
        var directories: [URL] = [pluginsDirectory]
        if let bundledPluginsDirectory {
            directories.append(bundledPluginsDirectory)
        }
        return loadPlugins(in: directories, disabledIDs: disabledIDs)
    }

    /// Loads plugins from explicit directories. Exposed internally so tests can use a
    /// temporary folder instead of the user's Application Support directory.
    func loadPlugins(
        in directories: [URL],
        disabledIDs: Set<String>
    ) -> (plugins: [InstalledPlugin], errors: [String]) {
        contexts.removeAll()
        commandHandlers.removeAll()
        exporterHandlers.removeAll()
        loadedIDs.removeAll()
        lastError = nil

        var plugins: [InstalledPlugin] = []
        var errors: [String] = []

        for url in discoverPluginURLs(in: directories) {
            do {
                plugins.append(try loadPlugin(at: url, disabledIDs: disabledIDs))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        plugins.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (plugins, errors)
    }

    func execute(commandID: String, context: PluginCommandContext) {
        lastError = nil
        guard let handler = commandHandlers[commandID], let js = handler.context else {
            lastError = "The plugin command is no longer loaded."
            return
        }

        guard let object = JSValue(newObjectIn: js) else {
            lastError = "The plugin command context could not be created."
            return
        }
        object.setObject(context.text, forKeyedSubscript: "text" as NSString)
        object.setObject(context.selection.location, forKeyedSubscript: "selectionStart" as NSString)
        object.setObject(context.selection.length, forKeyedSubscript: "selectionLength" as NSString)
        object.setObject(context.documentName, forKeyedSubscript: "documentName" as NSString)
        object.setObject(context.filePath ?? NSNull(), forKeyedSubscript: "filePath" as NSString)

        let insert: @convention(block) (String?) -> Void = { value in
            context.insertText(value ?? "")
        }
        let replace: @convention(block) (String?) -> Void = { value in
            context.replaceSelection(value ?? "")
        }
        let setText: @convention(block) (String?) -> Void = { value in
            context.setText(value ?? "")
        }
        let setSelection: @convention(block) (Double, Double) -> Void = { location, length in
            // JavaScript can hand us NaN, ±Infinity, or a value outside Int's range;
            // `Int(_:)` traps on all of those and would take the whole app down.
            context.setSelection(Self.safeOffset(location), Self.safeOffset(length))
        }
        let save: @convention(block) () -> Void = {
            context.save()
        }
        let alert: @convention(block) (String?, String?) -> Void = { title, message in
            context.alert(title ?? "Plugin", message ?? "")
        }
        let setAccent: @convention(block) (String?) -> Void = { hex in
            context.setAccent(hex ?? "")
        }
        let setPreviewTheme: @convention(block) (String?) -> Void = { name in
            context.setPreviewTheme(name ?? "")
        }
        let setAppearance: @convention(block) (String?) -> Void = { name in
            context.setAppearance(name ?? "")
        }

        object.setObject(unsafeBitCast(insert, to: AnyObject.self), forKeyedSubscript: "insertText" as NSString)
        object.setObject(unsafeBitCast(replace, to: AnyObject.self), forKeyedSubscript: "replaceSelection" as NSString)
        object.setObject(unsafeBitCast(setText, to: AnyObject.self), forKeyedSubscript: "setText" as NSString)
        object.setObject(unsafeBitCast(setSelection, to: AnyObject.self), forKeyedSubscript: "setSelection" as NSString)
        object.setObject(unsafeBitCast(save, to: AnyObject.self), forKeyedSubscript: "save" as NSString)
        object.setObject(unsafeBitCast(alert, to: AnyObject.self), forKeyedSubscript: "alert" as NSString)
        object.setObject(unsafeBitCast(setAccent, to: AnyObject.self), forKeyedSubscript: "setAccent" as NSString)
        object.setObject(unsafeBitCast(setPreviewTheme, to: AnyObject.self), forKeyedSubscript: "setPreviewTheme" as NSString)
        object.setObject(unsafeBitCast(setAppearance, to: AnyObject.self), forKeyedSubscript: "setAppearance" as NSString)

        _ = handler.call(withArguments: [object])
        captureException(from: js)
    }

    func exportHTML(
        exporterID: String,
        markdown: String,
        title: String,
        theme: PreviewTheme
    ) -> String? {
        lastError = nil
        guard let handler = exporterHandlers[exporterID], let js = handler.context else {
            lastError = "The plugin exporter is no longer loaded."
            return nil
        }

        guard let document = JSValue(newObjectIn: js) else {
            lastError = "The plugin exporter could not be prepared."
            return nil
        }
        document.setObject(markdown, forKeyedSubscript: "markdown" as NSString)
        document.setObject(title, forKeyedSubscript: "title" as NSString)
        document.setObject(theme.rawValue, forKeyedSubscript: "theme" as NSString)

        let result = handler.call(withArguments: [document])
        captureException(from: js)
        guard let result, !result.isUndefined, !result.isNull else {
            if lastError == nil { lastError = "The plugin exporter returned no output." }
            return nil
        }
        guard let html = result.toString(), !html.isEmpty else {
            if lastError == nil { lastError = "The plugin exporter returned no output." }
            return nil
        }
        return html
    }

    /// Converts a JS number to a safe `Int`, clamping non-finite and out-of-range values
    /// instead of trapping.
    static func safeOffset(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded(.towardZero)
        if rounded >= Double(Int.max) { return Int.max }
        if rounded <= Double(Int.min) { return Int.min }
        return Int(rounded)
    }

    /// Writes a small documented example plugin into the user's plugin folder.
    @discardableResult
    func installSamplePlugin() throws -> URL {
        let folder = pluginsDirectory.appendingPathComponent("hello-iris", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let manifest = """
        {
          "id": "hello-iris",
          "name": "Hello Iris",
          "version": "1.0.0",
          "author": "Iris Editor",
          "summary": "Example commands and an exporter.",
          "main": "main.js"
        }
        """
        let script = """
        // Iris Editor plugin API example.
        iris.registerCommand(
          { id: "word-count", title: "Plugin: Word Count" },
          function (ctx) {
            var words = ctx.text.trim().split(/\\s+/).filter(Boolean).length;
            ctx.alert("Word Count", words + " words");
          }
        );

        iris.registerCommand(
          { id: "insert-date", title: "Plugin: Insert ISO Date", shortcut: "command+option+d" },
          function (ctx) {
            ctx.insertText(new Date().toISOString().slice(0, 10));
          }
        );

        iris.registerCommand(
          { id: "night-theme", title: "Plugin: Night Theme" },
          function (ctx) {
            ctx.setAppearance("dark");
            ctx.setPreviewTheme("midnight");
            ctx.setAccent("#7C6CF0");
          }
        );

        iris.registerExporter(
          { id: "minimal-html", title: "Minimal HTML", extension: "html" },
          function (doc) {
            var escaped = doc.markdown
              .replace(/&/g, "&amp;")
              .replace(/</g, "&lt;")
              .replace(/>/g, "&gt;");
            return "<!DOCTYPE html><html><head><meta charset=\\"utf-8\\"><title>"
              + doc.title + "</title></head><body><pre>" + escaped + "</pre></body></html>";
          }
        );
        """

        try manifest.write(
            to: folder.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )
        try script.write(
            to: folder.appendingPathComponent("main.js"),
            atomically: true,
            encoding: .utf8
        )
        return folder
    }

    // MARK: - Discovery

    private func discoverPluginURLs(in directories: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()

        for directory in directories {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { continue }

                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let candidate: Bool
                if isDirectory {
                    candidate = FileManager.default.fileExists(atPath: url.appendingPathComponent("plugin.json").path)
                        || FileManager.default.fileExists(atPath: url.appendingPathComponent("main.js").path)
                } else {
                    candidate = url.pathExtension.lowercased() == "js"
                }

                guard candidate else { continue }
                let key = url.standardizedFileURL.path
                if seen.insert(key).inserted {
                    result.append(url)
                }
            }
        }
        return result
    }

    // MARK: - Loading

    private func loadPlugin(at url: URL, disabledIDs: Set<String>) throws -> InstalledPlugin {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let folder = isDirectory ? url : url.deletingLastPathComponent()
        let fallbackID = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent

        var manifest: PluginManifest?
        if isDirectory {
            let manifestURL = url.appendingPathComponent("plugin.json")
            if let data = try? Data(contentsOf: manifestURL) {
                manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
            }
        }

        // Two plugins may declare the same manifest id (or the same folder name in
        // different roots). Folding them into one id would let one plugin's menu entry run
        // the other's code, so the id is disambiguated with a short hash of its path.
        var pluginID = Self.sanitizedID(manifest?.id ?? fallbackID)
        if loadedIDs.contains(pluginID) {
            pluginID += "-" + Self.pathFingerprint(for: url)
        }
        loadedIDs.insert(pluginID)
        let name = manifest?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name! : fallbackID)
        let version = manifest?.version ?? "1.0"
        let author = manifest?.author ?? ""
        let summary = manifest?.summary ?? ""

        if disabledIDs.contains(pluginID) {
            return InstalledPlugin(
                id: pluginID,
                name: displayName,
                version: version,
                author: author,
                summary: summary,
                folderURL: folder,
                isEnabled: false,
                commands: [],
                exporters: []
            )
        }

        let scriptURL: URL
        if isDirectory {
            let entry = manifest?.main ?? "main.js"
            let resolved = folder.appendingPathComponent(entry).standardizedFileURL
            guard resolved.path.hasPrefix(folder.standardizedFileURL.path + "/") else {
                throw PluginError.escapedPluginFolder
            }
            scriptURL = resolved
        } else {
            scriptURL = url
        }

        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw PluginError.missingScript(scriptURL.path)
        }
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        return try evaluate(
            source: source,
            pluginID: pluginID,
            name: displayName,
            version: version,
            author: author,
            summary: summary,
            folderURL: folder
        )
    }

    private func evaluate(
        source: String,
        pluginID: String,
        name: String,
        version: String,
        author: String,
        summary: String,
        folderURL: URL
    ) throws -> InstalledPlugin {
        guard let context = JSContext() else {
            throw PluginError.invalidScript("Could not create a JavaScript context.")
        }

        let registration = PluginRegistration()

        let iris = JSValue(newObjectIn: context)
        let registerCommand: @convention(block) (JSValue?, JSValue?) -> Void = { meta, callback in
            guard let meta, let callback else { return }
            let rawID = meta.forProperty("id")?.toString() ?? "command-\(registration.commands.count)"
            let title = meta.forProperty("title")?.toString() ?? rawID
            let shortcut = meta.forProperty("shortcut")?.toString()
            let id = "\(pluginID).\(Self.sanitizedID(rawID))"
            registration.commands.append(
                PluginCommandDescriptor(
                    id: id,
                    title: title,
                    shortcut: shortcut,
                    pluginID: pluginID,
                    pluginName: name
                )
            )
            registration.commandHandlers[id] = callback
        }

        let registerExporter: @convention(block) (JSValue?, JSValue?) -> Void = { meta, callback in
            guard let meta, let callback else { return }
            let rawID = meta.forProperty("id")?.toString() ?? "exporter-\(registration.exporters.count)"
            let title = meta.forProperty("title")?.toString() ?? rawID
            let fileExtension = meta.forProperty("extension")?.toString() ?? "html"
            let id = "\(pluginID).\(Self.sanitizedID(rawID))"
            registration.exporters.append(
                PluginExporterDescriptor(
                    id: id,
                    title: title,
                    fileExtension: Self.sanitizedExtension(fileExtension),
                    pluginID: pluginID,
                    pluginName: name
                )
            )
            registration.exporterHandlers[id] = callback
        }

        let log: @convention(block) (String?) -> Void = { message in
            print("[plugin:\(pluginID)] \(message ?? "")")
        }

        iris?.setObject(
            unsafeBitCast(registerCommand, to: AnyObject.self),
            forKeyedSubscript: "registerCommand" as NSString
        )
        iris?.setObject(
            unsafeBitCast(registerExporter, to: AnyObject.self),
            forKeyedSubscript: "registerExporter" as NSString
        )
        iris?.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        iris?.setObject(pluginID, forKeyedSubscript: "id" as NSString)
        iris?.setObject(name, forKeyedSubscript: "name" as NSString)
        context.setObject(iris, forKeyedSubscript: "iris" as NSString)

        _ = context.evaluateScript(source, withSourceURL: folderURL.appendingPathComponent("main.js"))
        if let exception = context.exception {
            context.exception = nil
            throw PluginError.invalidScript(exception.toString() ?? "Unknown JavaScript error.")
        }

        contexts[pluginID] = context
        commandHandlers.merge(registration.commandHandlers) { _, new in new }
        exporterHandlers.merge(registration.exporterHandlers) { _, new in new }

        return InstalledPlugin(
            id: pluginID,
            name: name,
            version: version,
            author: author,
            summary: summary,
            folderURL: folderURL,
            isEnabled: true,
            commands: registration.commands,
            exporters: registration.exporters
        )
    }

    private func captureException(from context: JSContext) {
        guard let exception = context.exception else { return }
        context.exception = nil
        lastError = exception.toString() ?? "Unknown JavaScript error."
    }

    // MARK: - Naming

    /// Short stable fingerprint of a plugin's location, used to disambiguate equal ids.
    nonisolated static func pathFingerprint(for url: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash % 0xfffff, radix: 16)
    }

    nonisolated static func sanitizedID(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mapped = String(lowered.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
        let collapsed = mapped
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "plugin" : collapsed
    }

    nonisolated private static func sanitizedExtension(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? "html" : cleaned
    }
}

/// Collects registrations during one synchronous `evaluateScript` call. Keeping this
/// separate from the host avoids exposing mutable host state directly to JavaScript.
private final class PluginRegistration {
    var commands: [PluginCommandDescriptor] = []
    var exporters: [PluginExporterDescriptor] = []
    var commandHandlers: [String: JSValue] = [:]
    var exporterHandlers: [String: JSValue] = [:]
}
