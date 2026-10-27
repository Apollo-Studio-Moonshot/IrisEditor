import Foundation

// MARK: - Panes

/// Sections available in the vault sidebar.
enum VaultPane: String, CaseIterable, Identifiable, Sendable {
    case files, outline, tags, backlinks, graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .outline: "Outline"
        case .tags: "Tags"
        case .backlinks: "Backlinks"
        case .graph: "Graph"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "folder"
        case .outline: "list.bullet.indent"
        case .tags: "number"
        case .backlinks: "link"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }
}

// MARK: - Value types

/// A Markdown document discovered inside a vault folder.
struct VaultFile: Identifiable, Equatable, Hashable, Sendable {
    let url: URL
    let name: String
    let title: String
    let relativePath: String
    let modified: Date

    var id: URL { url }
}

/// A folder in the vault tree. `id` and `relativePath` use "/" separators; the root is `""`.
struct VaultFolder: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let relativePath: String
    let files: [VaultFile]
    let subfolders: [VaultFolder]

    /// Number of documents in this folder and all of its descendants.
    var fileCount: Int {
        files.count + subfolders.reduce(0) { $0 + $1.fileCount }
    }
}

struct VaultTag: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

struct VaultBacklink: Identifiable, Equatable, Sendable {
    let sourceURL: URL
    let sourceTitle: String
    let line: Int
    let excerpt: String

    var id: String { "\(sourceURL.path)#\(line)" }
}

struct VaultSearchResult: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String
    let line: Int
    let excerpt: String

    var id: String { "\(url.path)#\(line)" }
}

struct VaultGraphNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let isCurrent: Bool
    let linkCount: Int
}

struct VaultGraphEdge: Identifiable, Equatable, Sendable {
    let source: String
    let target: String

    var id: String { "\(source)->\(target)" }
}

struct VaultGraph: Equatable, Sendable {
    let nodes: [VaultGraphNode]
    let edges: [VaultGraphEdge]
}

// MARK: - Scanner

/// Pure-Foundation helpers that turn a vault folder into the data the sidebar needs.
enum VaultScanner {

    /// Recursively collects `.md` / `.markdown` files, skipping hidden and generated folders.
    static func markdownFiles(in root: URL, limit: Int = 2000) -> [VaultFile] {
        guard limit > 0 else { return [] }

        let skippedNames: Set<String> = ["assets", "node_modules", ".git", ".trash"]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [VaultFile] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if skippedNames.contains(name.lowercased()) {
                enumerator.skipDescendants()
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true,
                  values?.isDirectory != true else {
                continue
            }

            files.append(
                VaultFile(
                    url: url,
                    name: name,
                    title: url.deletingPathExtension().lastPathComponent,
                    relativePath: relativePath(of: url, in: root),
                    modified: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        if files.count > limit {
            files.removeLast(files.count - limit)
        }
        return files
    }

    /// Builds a nested folder tree from the files' `relativePath` values.
    static func folderTree(files: [VaultFile]) -> VaultFolder {
        buildFolder(name: rootName(for: files), relativePath: "", files: files, depth: 0)
    }

    /// Aggregate tag counts across files (counts how many files mention each tag).
    static func tags(in files: [VaultFile]) -> [VaultTag] {
        var spellings: [String: String] = [:]
        var counts: [String: Int] = [:]

        for file in files {
            guard let text = readText(file.url) else { continue }
            for tag in tags(inText: text) {
                let key = tag.lowercased()
                if spellings[key] == nil { spellings[key] = tag }
                counts[key, default: 0] += 1
            }
        }

        return counts.map { VaultTag(name: spellings[$0.key] ?? $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Inline `#tags` plus frontmatter tags, ignoring headings, code, and URL fragments.
    static func tags(inText text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func add(_ raw: String) {
            var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while name.hasPrefix("#") { name.removeFirst() }
            while name.hasSuffix("/") { name.removeLast() }
            guard !name.isEmpty else { return }
            let key = name.lowercased()
            guard seen.insert(key).inserted else { return }
            result.append(name)
        }

        let frontmatter = MarkdownFrontmatterParser.parse(text)
        for tag in frontmatter?.tags ?? [] {
            add(tag)
        }

        let body = frontmatter?.body ?? text
        let lines = normalizedLines(body)
        let regex = Patterns.tag

        var fence: Character?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fence {
                if trimmed.hasPrefix(String(repeating: String(marker), count: 3)) {
                    fence = nil
                }
                continue
            }
            if let marker = fenceStart(trimmed) {
                fence = marker
                continue
            }
            if isATXHeading(trimmed) { continue }

            let masked = maskingInlineCode(line)
            guard let regex else { continue }
            let string = masked as NSString
            let matches = regex.matches(in: masked, range: NSRange(location: 0, length: string.length))
            for match in matches {
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { continue }
                add(string.substring(with: range))
            }
        }

        return result
    }

    /// Every `[[wiki link]]` in a vault that points at `url`, with line and excerpt.
    static func backlinks(to url: URL, in files: [VaultFile]) -> [VaultBacklink] {
        let targetPath = url.standardizedFileURL.path
        let targetFile = files.first { $0.url.standardizedFileURL.path == targetPath }

        var aliases = Set<String>()
        let title = (targetFile?.title ?? url.deletingPathExtension().lastPathComponent).lowercased()
        if !title.isEmpty { aliases.insert(title) }
        if let targetFile {
            let path = strippingExtension(targetFile.relativePath).lowercased()
            if !path.isEmpty { aliases.insert(path) }
        }

        let aliasMap = aliasMap(for: files)
        var results: [VaultBacklink] = []
        var seen = Set<String>()

        for file in files where file.url.standardizedFileURL.path != targetPath {
            guard let text = readText(file.url) else { continue }
            let lines = normalizedLines(text)

            for (index, line) in lines.enumerated() {
                guard line.contains("[[") else { continue }

                let isTarget = wikiTargets(inText: line).contains { target in
                    let lowered = target.lowercased()
                    if aliases.contains(lowered) { return true }
                    if aliases.contains(strippingExtension(lowered)) { return true }
                    if let resolved = resolveTarget(target, aliases: aliasMap, filesByPath: [:]) {
                        return resolved.standardizedFileURL.path == targetPath
                    }
                    return false
                }
                guard isTarget else { continue }

                let lineNumber = index + 1
                guard seen.insert("\(file.url.path)#\(lineNumber)").inserted else { continue }
                results.append(
                    VaultBacklink(
                        sourceURL: file.url,
                        sourceTitle: file.title,
                        line: lineNumber,
                        excerpt: prefixExcerpt(line, limit: 120)
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            let order = lhs.sourceTitle.localizedStandardCompare(rhs.sourceTitle)
            if order != .orderedSame { return order == .orderedAscending }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.sourceURL.path < rhs.sourceURL.path
        }
    }

    /// Nodes and edges for the current note plus its direct (or `depth`-step) neighbours.
    static func graph(around url: URL?, in files: [VaultFile], depth: Int = 1) -> VaultGraph {
        guard !files.isEmpty else { return VaultGraph(nodes: [], edges: []) }

        let aliasMap = aliasMap(for: files)
        var filesByPath: [String: VaultFile] = [:]
        for file in files {
            filesByPath[file.url.standardizedFileURL.path] = file
        }

        var outgoing: [String: Set<String>] = [:]
        for file in files {
            guard let text = readText(file.url) else { continue }
            let source = file.url.standardizedFileURL.path
            for target in wikiTargets(inText: text) {
                if let resolved = resolveTarget(target, aliases: aliasMap, filesByPath: filesByPath) {
                    outgoing[source, default: []].insert(resolved.standardizedFileURL.path)
                }
            }
        }

        var neighbours: [String: Set<String>] = [:]
        for (source, targets) in outgoing {
            for target in targets {
                neighbours[source, default: []].insert(target)
                neighbours[target, default: []].insert(source)
            }
        }

        var included: [String] = []
        var includedSet = Set<String>()

        if let url {
            let start = url.standardizedFileURL.path
            let maxDepth = max(0, min(depth, 4))
            var frontier = [start]
            included.append(start)
            includedSet.insert(start)

            var level = 0
            while level < maxDepth, !frontier.isEmpty, included.count < 60 {
                var next: [String] = []
                for node in frontier {
                    for neighbour in (neighbours[node] ?? []).sorted() {
                        guard included.count < 60 else { break }
                        if includedSet.insert(neighbour).inserted {
                            included.append(neighbour)
                            next.append(neighbour)
                        }
                    }
                }
                frontier = next
                level += 1
            }
        } else {
            let sorted = files.sorted { lhs, rhs in
                let order = lhs.title.localizedStandardCompare(rhs.title)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.url.path < rhs.url.path
            }
            for file in sorted.prefix(60) {
                let path = file.url.standardizedFileURL.path
                guard includedSet.insert(path).inserted else { continue }
                included.append(path)
            }
        }

        if included.count > 60 {
            included.removeLast(included.count - 60)
            includedSet = Set(included)
        }

        func nodeID(for path: String) -> String {
            filesByPath[path]?.url.path ?? path
        }

        var edges: [VaultGraphEdge] = []
        var seenEdges = Set<String>()
        for (source, targets) in outgoing {
            guard includedSet.contains(source) else { continue }
            for target in targets where includedSet.contains(target) {
                let edge = VaultGraphEdge(source: nodeID(for: source), target: nodeID(for: target))
                guard seenEdges.insert(edge.id).inserted else { continue }
                edges.append(edge)
            }
        }
        edges.sort { lhs, rhs in
            let sourceOrder = lhs.source.localizedStandardCompare(rhs.source)
            if sourceOrder != .orderedSame { return sourceOrder == .orderedAscending }
            return lhs.target.localizedStandardCompare(rhs.target) == .orderedAscending
        }

        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.source, default: 0] += 1
            degree[edge.target, default: 0] += 1
        }

        let currentPath = url?.standardizedFileURL.path
        let nodes = included.map { path -> VaultGraphNode in
            let file = filesByPath[path]
            let title = file?.title
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let id = nodeID(for: path)
            return VaultGraphNode(
                id: id,
                title: title,
                isCurrent: currentPath == path,
                linkCount: degree[id] ?? 0
            )
        }

        return VaultGraph(nodes: nodes, edges: edges)
    }

    /// Case-insensitive substring search, one result per matching line.
    static func search(_ query: String, in files: [VaultFile], limit: Int = 60) -> [VaultSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }

        var results: [VaultSearchResult] = []
        for file in files {
            guard results.count < limit else { break }
            guard !isTooLarge(file.url) else { continue }
            guard let text = readText(file.url), !text.contains("\0") else { continue }

            for (index, line) in normalizedLines(text).enumerated() {
                guard results.count < limit else { break }
                guard line.range(of: needle, options: [.caseInsensitive]) != nil else { continue }
                results.append(
                    VaultSearchResult(
                        url: file.url,
                        title: file.title,
                        line: index + 1,
                        excerpt: centeredExcerpt(line, needle: needle, limit: 160)
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            let order = lhs.title.localizedStandardCompare(rhs.title)
            if order != .orderedSame { return order == .orderedAscending }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.url.path < rhs.url.path
        }
    }

    /// Unique note titles (filename without extension), sorted for autocomplete.
    static func allWikiTargets(in files: [VaultFile]) -> [String] {
        var seen = Set<String>()
        var titles: [String] = []
        for file in files {
            let key = file.title.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            titles.append(file.title)
        }
        return titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Folder tree

    private static func buildFolder(
        name: String,
        relativePath: String,
        files: [VaultFile],
        depth: Int
    ) -> VaultFolder {
        let prefix = relativePath.isEmpty ? "" : relativePath + "/"
        var directFiles: [VaultFile] = []
        var grouped: [String: [VaultFile]] = [:]

        for file in files {
            var rest = file.relativePath
            if !prefix.isEmpty, rest.hasPrefix(prefix) {
                rest.removeFirst(prefix.count)
            }
            let components = rest.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count > 1 else {
                directFiles.append(file)
                continue
            }
            grouped[String(components[0]), default: []].append(file)
        }

        let names = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let subfolders = names.map { child -> VaultFolder in
            let childPath = prefix + child
            let childFiles = (grouped[child] ?? []).sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            guard depth < 32 else {
                return VaultFolder(
                    id: childPath,
                    name: child,
                    relativePath: childPath,
                    files: childFiles,
                    subfolders: []
                )
            }
            return buildFolder(
                name: child,
                relativePath: childPath,
                files: grouped[child] ?? [],
                depth: depth + 1
            )
        }

        return VaultFolder(
            id: relativePath,
            name: name,
            relativePath: relativePath,
            files: directFiles.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            },
            subfolders: subfolders
        )
    }

    /// The vault root name inferred from the first file's URL and relative path.
    private static func rootName(for files: [VaultFile]) -> String {
        guard let first = files.first else { return "Vault" }
        let components = first.url.pathComponents
        let depth = components.count - first.relativePath.split(separator: "/").count
        guard depth > 0, depth <= components.count else { return "Vault" }
        guard let name = Array(components.prefix(depth)).last,
              !name.isEmpty,
              name != "/" else {
            return "Vault"
        }
        return name
    }

    // MARK: - Resolution

    private static func aliasMap(for files: [VaultFile]) -> [String: URL] {
        var map: [String: URL] = [:]
        for file in files {
            let keys = [
                file.title.lowercased(),
                strippingExtension(file.relativePath).lowercased()
            ]
            for key in keys where !key.isEmpty {
                if map[key] == nil { map[key] = file.url }
            }
        }
        return map
    }

    private static func resolveTarget(
        _ target: String,
        aliases: [String: URL],
        filesByPath: [String: VaultFile]
    ) -> URL? {
        let lowered = target.lowercased()
        for candidate in [lowered, strippingExtension(lowered)] {
            if let url = aliases[candidate] {
                if filesByPath.isEmpty { return url }
                if let file = filesByPath[url.standardizedFileURL.path] { return file.url }
            }
        }
        return nil
    }

    private static func strippingExtension(_ path: String) -> String {
        let lowered = path.lowercased()
        for ext in [".md", ".markdown"] where lowered.hasSuffix(ext) {
            return String(path.dropLast(ext.count))
        }
        return path
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else {
            return url.lastPathComponent
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    // MARK: - Text helpers

    private static func readText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func fenceStart(_ trimmed: String) -> Character? {
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func isATXHeading(_ trimmed: String) -> Bool {
        var hashes = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#" {
            hashes += 1
            index = trimmed.index(after: index)
        }
        guard (1...6).contains(hashes) else { return false }
        guard index < trimmed.endIndex else { return true }
        let next = trimmed[index]
        return next == " " || next == "\t"
    }

    /// Replaces inline code spans with spaces so tags inside them are never matched.
    private static func maskingInlineCode(_ line: String) -> String {
        var masked = ""
        var inside = false
        for character in line {
            if character == "`" {
                inside.toggle()
                masked.append(" ")
            } else {
                masked.append(inside ? " " : character)
            }
        }
        return masked
    }

    /// Extracts wiki-link targets from text, dropping `|labels` and `#fragments`.
    private static func wikiTargets(inText text: String) -> [String] {
        guard let regex = Patterns.wikiLink else { return [] }
        let string = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: string.length))

        var targets: [String] = []
        for match in matches {
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            let inner = string.substring(with: range)

            var target = inner
            if let pipe = target.firstIndex(of: "|") { target = String(target[..<pipe]) }
            if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
            target = target.trimmingCharacters(in: .whitespacesAndNewlines)
            while target.hasPrefix("/") { target.removeFirst() }
            guard !target.isEmpty else { continue }
            targets.append(target)
        }
        return targets
    }

    private static func prefixExcerpt(_ line: String, limit: Int) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private static func centeredExcerpt(
        _ line: String,
        needle: String,
        limit: Int
    ) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }

        guard let range = trimmed.range(of: needle, options: [.caseInsensitive]) else {
            return prefixExcerpt(trimmed, limit: limit)
        }

        let characters = Array(trimmed)
        let matchStart = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
        let matchLength = trimmed.distance(from: range.lowerBound, to: range.upperBound)

        var start = max(0, matchStart - max(0, (limit - matchLength) / 2))
        var end = min(characters.count, start + limit)
        if end - start < limit {
            start = max(0, end - limit)
            end = min(characters.count, start + limit)
        }
        guard start < end else { return trimmed }

        var excerpt = String(characters[start..<end])
        if start > 0 { excerpt = "…" + excerpt }
        if end < characters.count { excerpt += "…" }
        return excerpt
    }

    private static func isTooLarge(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { return false }
        return size > 2 * 1024 * 1024
    }
}

// MARK: - Daily notes

enum DailyNotes {

    /// Path of the daily note for `date`: `<root>/<folder>/yyyy-MM-dd.md`.
    static func noteURL(
        for date: Date,
        in root: URL,
        folderName: String = "Daily Notes",
        format: String = "yyyy-MM-dd"
    ) -> URL {
        let formatter = makeFormatter(format: format)
        let fileName = formatter.string(from: date) + ".md"
        guard !folderName.isEmpty else {
            return root.appendingPathComponent(fileName, isDirectory: false)
        }
        return root
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Starter Markdown for a new daily note.
    static func defaultTemplate(date: Date, formatter: DateFormatter? = nil) -> String {
        let formatted = formatter.map { $0.string(from: date) }
            ?? makeFormatter(format: "yyyy-MM-dd").string(from: date)
        return "# \(formatted)\n\n## Tasks\n\n- [ ] "
    }

    private static func makeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Compiled patterns

private enum Patterns {
    // NSRegularExpression instances are immutable and safe to share across threads.
    static let wikiLink = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+)\]\]"#)
    static let tag = try? NSRegularExpression(pattern: #"(?:^|(?<=\s))#([\p{L}\p{N}_\-/]+)"#)
}
