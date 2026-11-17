import Foundation

// MARK: - Panes

/// Sections available in the vault sidebar.
///
/// Order matters: it is the order of the pane picker in the sidebar header.
enum VaultPane: String, CaseIterable, Identifiable, Sendable {
    case files, outline, tags, backlinks, stars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .outline: "Outline"
        case .tags: "Tags"
        case .backlinks: "Backlinks"
        case .stars: "Starred"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "folder"
        case .outline: "list.bullet.indent"
        case .tags: "number"
        case .backlinks: "link"
        case .stars: "star"
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
    static func backlinks(to url: URL, in files: [VaultFile]) -> [VaultBacklink] {        let targetPath = url.standardizedFileURL.path
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

    /// Plain-text mentions of `url`'s title that are not wiki links yet.
    ///
    /// This is Obsidian's "unlinked mentions" pane: the same alias set as `backlinks(to:)`,
    /// matched on word boundaries in prose while ignoring fenced and inline code.
    static func unlinkedMentions(of url: URL, in files: [VaultFile]) -> [VaultBacklink] {
        let targetPath = url.standardizedFileURL.path
        let targetFile = files.first { $0.url.standardizedFileURL.path == targetPath }

        var needles = Set<String>()
        let title = (targetFile?.title ?? url.deletingPathExtension().lastPathComponent)
        if title.count >= 2 { needles.insert(title) }
        if let targetFile {
            let path = strippingExtension(targetFile.relativePath)
            if path.count >= 2, path.lowercased() != title.lowercased() { needles.insert(path) }
        }
        guard !needles.isEmpty else { return [] }

        let patterns = needles.compactMap { needle -> NSRegularExpression? in
            let escaped = NSRegularExpression.escapedPattern(for: needle)
            let pattern = "(?i)(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            return try? NSRegularExpression(pattern: pattern)
        }
        guard !patterns.isEmpty else { return [] }

        var results: [VaultBacklink] = []
        var seen = Set<String>()

        for file in files where file.url.standardizedFileURL.path != targetPath {
            guard let text = readText(file.url) else { continue }
            let lines = normalizedLines(text)
            var inFence = false

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if fenceStart(trimmed) != nil {
                    inFence.toggle()
                    continue
                }
                guard !inFence else { continue }
                // Lines that already link the note stay in the backlinks pane.
                guard !line.contains("[[") else { continue }

                let masked = maskingInlineCode(line)
                let range = NSRange(location: 0, length: (masked as NSString).length)
                let matches = patterns.contains {
                    $0.firstMatch(in: masked, range: range) != nil
                }
                guard matches else { continue }

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

    /// Case-insensitive substring search, one result per matching line.
    static func search(_ query: String, in files: [VaultFile], limit: Int = 60) -> [VaultSearchResult] {
        let parsed = VaultQuery.parse(query)
        guard !parsed.isEmpty, limit > 0 else { return [] }

        var results: [VaultSearchResult] = []
        for file in files {
            guard results.count < limit else { break }
            guard parsed.matchesFile(file) else { continue }
            guard !isTooLarge(file.url) else { continue }
            guard let text = readText(file.url), !text.contains("\0") else { continue }
            guard parsed.matchesMetadata(of: text) else { continue }

            // A filter-only query (`tag:idea`) lists the whole note rather than every
            // matching line, which is what Obsidian does.
            guard !parsed.text.isEmpty else {
                let firstLine = normalizedLines(text).first ?? ""
                results.append(
                    VaultSearchResult(
                        url: file.url,
                        title: file.title,
                        line: 1,
                        excerpt: String(firstLine.prefix(160))
                    )
                )
                continue
            }

            let options: String.CompareOptions = parsed.matchCase ? [] : [.caseInsensitive]
            for (index, line) in normalizedLines(text).enumerated() {
                guard results.count < limit else { break }
                guard line.range(of: parsed.text, options: options) != nil else { continue }
                results.append(
                    VaultSearchResult(
                        url: file.url,
                        title: file.title,
                        line: index + 1,
                        excerpt: centeredExcerpt(line, needle: parsed.text, limit: 160)
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

    /// Body text of a note, or `nil` when it is missing or too large to index.
    static func bodyText(of url: URL) -> String? {
        guard !isTooLarge(url), let text = readText(url) else { return nil }
        return MarkdownFrontmatterParser.parse(text)?.body ?? text
    }

    /// One snippet per matching note (the first matching line), for the sidebar search.
    ///
    /// Unlike ``search(_:in:limit:)`` this collapses all hits in a note to a single row,
    /// which is what a compact sidebar list needs. Results favour the current folder,
    /// then titles that start with the query, then recency.
    static func matchingNotes(
        _ query: String,
        in files: [VaultFile],
        limit: Int = 40
    ) -> [VaultSearchResult] {
        let parsed = VaultQuery.parse(query)
        guard !parsed.isEmpty, limit > 0 else { return [] }

        let options: String.CompareOptions = parsed.matchCase ? [] : [.caseInsensitive]
        let plain = parsed.text.trimmingCharacters(in: .whitespaces)

        var scored: [(result: VaultSearchResult, score: Int)] = []
        for file in files {
            guard parsed.matchesFile(file) else { continue }
            let titleHit = !plain.isEmpty && file.title.range(of: plain, options: options) != nil
            // Title-only filters never read the body, keeping huge vaults responsive.
            let needsText = !parsed.contentFragments.isEmpty
                || !parsed.tags.isEmpty
                || !parsed.excludedTags.isEmpty
                || (!titleHit && !plain.isEmpty)
            guard needsText else {
                scored.append((VaultSearchResult(url: file.url, title: file.title, line: 1, excerpt: ""), 3))
                continue
            }
            guard let text = bodyText(of: file.url),
                  parsed.matchesMetadata(of: text) else { continue }

            var lineNumber = 0
            var excerpt = ""
            if !plain.isEmpty, !titleHit {
                let lines = normalizedLines(text)
                guard let match = lines.firstIndex(where: {
                    $0.range(of: plain, options: options) != nil
                }) else { continue }
                lineNumber = match + 1
                excerpt = centeredExcerpt(lines[match], needle: plain, limit: 120)
            }
            var score = titleHit ? 4 : 0
            if titleHit, file.title.lowercased().hasPrefix(plain.lowercased()) { score += 2 }
            if plain.isEmpty { score += 1 }
            scored.append((
                VaultSearchResult(url: file.url, title: file.title, line: lineNumber, excerpt: excerpt),
                score
            ))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.result.title.localizedStandardCompare(rhs.result.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.result)
    }

    /// Notes modified inside the last `days` days, newest first.
    static func recentNotes(in files: [VaultFile], days: Int = 30, limit: Int = 50) -> [VaultFile] {
        guard limit > 0 else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(max(1, days)) * 86_400)
        return files
            .filter { $0.modified >= cutoff }
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }

    /// Notes in the same folder as `url`, current note first.
    static func siblings(of url: URL, in files: [VaultFile]) -> [VaultFile] {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path
        let matches = files.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL.path == folder
        }
        let current = url.standardizedFileURL
        return matches.sorted { lhs, rhs in
            let lhsCurrent = lhs.url.standardizedFileURL == current
            let rhsCurrent = rhs.url.standardizedFileURL == current
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Sorts a flat slice of notes for the files pane's "All Notes" listing.
    static func sorted(_ files: [VaultFile], by sort: VaultFileSort, ascending: Bool) -> [VaultFile] {
        func comparison(_ lhs: VaultFile, _ rhs: VaultFile) -> ComparisonResult {
            let primary: ComparisonResult
            switch sort {
            case .name:
                primary = lhs.relativePath.localizedStandardCompare(rhs.relativePath)
            case .modified, .created, .size:
                let lhsValue = sortValue(lhs, sort: sort)
                let rhsValue = sortValue(rhs, sort: sort)
                if lhsValue != rhsValue {
                    primary = lhsValue < rhsValue ? .orderedAscending : .orderedDescending
                } else {
                    primary = .orderedSame
                }
            }
            guard primary == .orderedSame else { return primary }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath)
        }
        return files.sorted { lhs, rhs in
            let order = comparison(lhs, rhs)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func sortValue(_ file: VaultFile, sort: VaultFileSort) -> Date {
        guard let values = try? file.url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey
        ]) else {
            switch sort {
            case .name, .modified: return file.modified
            case .created: return .distantPast
            case .size: return Date(timeIntervalSince1970: 0)
            }
        }
        switch sort {
        case .name, .modified:
            return values.contentModificationDate ?? file.modified
        case .created:
            return values.creationDate ?? .distantPast
        case .size:
            return Date(timeIntervalSince1970: TimeInterval(values.fileSize ?? 0))
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

    /// Resolves a wikilink or transclusion target to a vault file.
    ///
    /// Accepts a bare title (`Design notes`), a path relative to the vault root
    /// (`projects/Design notes`), and an optional `.md` extension — the same forms
    /// Obsidian accepts, matched case-insensitively.
    static func resolve(_ target: String, in files: [VaultFile]) -> VaultFile? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !files.isEmpty else { return nil }
        let filesByPath = Dictionary(
            files.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let url = resolveTarget(
            trimmed,
            aliases: aliasMap(for: files),
            filesByPath: filesByPath
        ) else { return nil }
        return filesByPath[url.standardizedFileURL.path]
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

    static func relativePath(of url: URL, in root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else {
            return url.lastPathComponent
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// Number of notes whose relative path contains `fragment`, for folder hints.
    static func count(in files: [VaultFile], matching fragment: String) -> Int {
        guard !fragment.isEmpty else { return files.count }
        return files.reduce(0) { $0 + ($1.relativePath.contains(fragment) ? 1 : 0) }
    }

    /// Directory of `url` relative to `root` (`""` when the file sits at the root).
    static func relativeDirectory(of url: URL, in root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else {
            return ""
        }
        return fileComponents
            .dropFirst(rootComponents.count)
            .dropLast()
            .joined(separator: "/")
    }

    // MARK: - Text helpers

    private static func readText(_ url: URL) -> String? {
        var encoding: String.Encoding = .utf8
        guard let text = try? String(contentsOf: url, usedEncoding: &encoding) else {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return text
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


/// A parsed vault search query with Obsidian-style operators.
///
/// Supported: `tag:name` (any depth, `tag:#a/b` and `-tag:` work), `path:fragment`,
/// `file:fragment`, `content:needle` (body text only), `title:needle` (titles only),
/// `match-case:` / `ignore-case:`, and quoted values (`tag:"needs review"`).
/// Everything else is the free-text needle, which is matched case-insensitively by default.
struct VaultQuery: Equatable {
    var text: String = ""
    var tags: [String] = []
    var excludedTags: [String] = []
    var pathFragments: [String] = []
    var excludedPathFragments: [String] = []
    var nameFragments: [String] = []
    var excludedNameFragments: [String] = []
    /// Body-only needles: match the note if the text appears anywhere in its contents.
    var contentFragments: [String] = []
    var matchCase: Bool = false

    /// Every free-text needle, including `content:` terms.
    var needles: [String] {
        ([text].filter { !$0.isEmpty } + contentFragments)
    }

    var isEmpty: Bool {
        text.isEmpty && tags.isEmpty && excludedTags.isEmpty && pathFragments.isEmpty
            && excludedPathFragments.isEmpty && nameFragments.isEmpty
            && excludedNameFragments.isEmpty && contentFragments.isEmpty
    }

    static func parse(_ raw: String) -> VaultQuery {
        var query = VaultQuery()
        var pending: [String] = []

        for token in tokenize(raw) {
            var body = token
            var isNegated = false
            if body.hasPrefix("-") {
                isNegated = true
                body.removeFirst()
            }
            guard let colon = body.firstIndex(of: ":") else {
                pending.append(isNegated ? "-" + body : body)
                continue
            }
            let key = body[body.startIndex..<colon].lowercased()
            let rawValue = String(body[body.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            let value = rawValue.hasPrefix("#") ? String(rawValue.dropFirst()) : rawValue

            switch key {
            case "tag":
                guard !value.isEmpty else { break }
                if isNegated { query.excludedTags.append(value.lowercased()) }
                else { query.tags.append(value.lowercased()) }
            case "path":
                guard !value.isEmpty else { break }
                if isNegated { query.excludedPathFragments.append(value.lowercased()) }
                else { query.pathFragments.append(value.lowercased()) }
            case "file", "filename":
                guard !value.isEmpty else { break }
                if isNegated { query.excludedNameFragments.append(value.lowercased()) }
                else { query.nameFragments.append(value.lowercased()) }
            case "content":
                guard !value.isEmpty else { break }
                // A negated content filter has no meaning for line search; ignore it.
                if !isNegated { query.contentFragments.append(value) }
            case "title", "name":
                guard !value.isEmpty else { break }
                if isNegated { query.excludedNameFragments.append(value.lowercased()) }
                else { query.nameFragments.append(value.lowercased()) }
            case "match-case":
                query.matchCase = true
            case "ignore-case":
                query.matchCase = false
            default:
                // Not an operator: keep it as text so `time: 10` still searches.
                pending.append(isNegated ? "-" + body : body)
            }
        }

        query.text = pending.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return query
    }

    /// Splits on whitespace while keeping `"quoted values"` together.
    private static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in raw {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character.isWhitespace, !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// File-level filters: path, name, and tags that appear anywhere in the note.
    func matchesFile(_ file: VaultFile) -> Bool {
        let path = file.relativePath.lowercased()
        let name = file.title.lowercased()

        for fragment in pathFragments where !path.contains(fragment) { return false }
        for fragment in excludedPathFragments where path.contains(fragment) { return false }
        for fragment in nameFragments where !name.contains(fragment) { return false }
        for fragment in excludedNameFragments where name.contains(fragment) { return false }
        return true
    }

    /// Tag and content filters need the file's text, so they run after it has been read.
    func matchesMetadata(of text: String) -> Bool {
        guard !tags.isEmpty || !excludedTags.isEmpty || !contentFragments.isEmpty else { return true }
        for fragment in contentFragments {
            let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
            guard text.range(of: fragment, options: options) != nil else { return false }
        }
        guard !tags.isEmpty || !excludedTags.isEmpty else { return true }
        let present = Set(VaultScanner.tags(inText: text).map { $0.lowercased() })
        for tag in tags where !present.contains(where: { $0 == tag || $0.hasPrefix(tag + "/") }) {
            return false
        }
        for tag in excludedTags where present.contains(where: { $0 == tag || $0.hasPrefix(tag + "/") }) {
            return false
        }
        return true
    }
}
