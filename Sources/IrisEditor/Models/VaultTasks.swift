import Foundation

/// One checkbox in a vault note. `line` is 1-based in the note's source.
struct VaultTask: Equatable, Sendable, Identifiable {
    let sourceURL: URL
    let relativePath: String
    let sourceTitle: String
    let line: Int
    let text: String

    var id: String { "\(sourceURL.standardizedFileURL.path)#\(line)" }
}

/// Parses and rewrites Markdown task lines.
///
/// Fenced code is ignored, so a sample checkbox inside a code block never becomes
/// a vault task. Empty checkboxes (`- [ ]` with no label) are ignored too.
enum VaultTaskIndex {
    /// Fence language that the preview replaces with the live open-task list.
    static let fenceLanguage = "iris-tasks"

    /// Markdown the daily note and the Insert Open Tasks command share.
    static let fenceBlock = "```iris-tasks\n```"

    struct ParsedTask: Equatable, Sendable {
        let line: Int
        let text: String
        let checked: Bool
    }

    /// Every labelled task in `text`, in source order.
    static func tasks(in text: String) -> [ParsedTask] {
        let lines = normalizedLines(text)
        var fence: Character?
        var tasks: [ParsedTask] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(String(repeating: String(marker), count: 3)) {
                    fence = nil
                }
                continue
            }
            if let marker = fenceMarker(trimmed) {
                fence = marker
                continue
            }
            guard let parsed = parseTaskLine(line) else { continue }
            tasks.append(
                ParsedTask(line: index + 1, text: parsed.text, checked: parsed.checked)
            )
        }
        return tasks
    }

    /// Returns `text` with the matching task's checkbox set to `checked`.
    ///
    /// `preferredLine` wins when that line is still the same task. Otherwise the
    /// first labelled task with the same text is updated. Returns nil when no
    /// line matches, so a caller can leave the file untouched.
    static func settingChecked(
        _ checked: Bool,
        taskText: String,
        preferredLine: Int,
        in text: String
    ) -> String? {
        let needle = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        var lines = normalizedLines(text)
        let candidates = taskLineIndexes(in: lines)
        guard !candidates.isEmpty else { return nil }

        let preferred = preferredLine - 1
        let index: Int
        if candidates.contains(preferred), parseTaskLine(lines[preferred])?.text == needle {
            index = preferred
        } else if let fallback = candidates.first(where: { parseTaskLine(lines[$0])?.text == needle }) {
            index = fallback
        } else {
            return nil
        }

        guard let updated = replacingCheckbox(in: lines[index], checked: checked) else {
            return nil
        }
        lines[index] = updated
        return lines.joined(separator: "\n")
    }

    // MARK: - Lines

    private static func taskLineIndexes(in lines: [String]) -> [Int] {
        var fence: Character?
        var indexes: [Int] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(String(repeating: String(marker), count: 3)) {
                    fence = nil
                }
                continue
            }
            if let marker = fenceMarker(trimmed) {
                fence = marker
                continue
            }
            if parseTaskLine(line) != nil {
                indexes.append(index)
            }
        }
        return indexes
    }

    private static func parseTaskLine(_ line: String) -> (checked: Bool, text: String)? {
        guard let regex = taskExpression,
              let match = regex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: (line as NSString).length)
              ),
              let markerRange = Range(match.range(at: 2), in: line),
              let textRange = Range(match.range(at: 4), in: line) else {
            return nil
        }
        let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let marker = String(line[markerRange])
        return (marker.lowercased() == "x", text)
    }

    private static func replacingCheckbox(in line: String, checked: Bool) -> String? {
        guard let regex = taskExpression,
              let match = regex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: (line as NSString).length)
              ),
              let markerRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return line.replacingCharacters(in: markerRange, with: checked ? "x" : " ")
    }

    private static func fenceMarker(_ trimmed: String) -> Character? {
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static let taskExpression = try? NSRegularExpression(
        pattern: #"^([ \t]*(?:[-*+]|[0-9]+[.)])[ \t]+\[)([ xX])(\][ \t]+)(.*)$"#
    )
}

/// A wiki link that points at a heading in another note.
struct VaultHeadingReference: Equatable, Sendable {
    let sourceURL: URL
    let sourceTitle: String
    let line: Int
    let excerpt: String
    let targetURL: URL
    /// Heading fragment after `#`, without the `|label`.
    let heading: String
}

/// Open tasks and heading links collected from one pass over the vault.
struct VaultDerivedSnapshot: Equatable, Sendable {
    var openTasks: [VaultTask]
    var headingReferences: [VaultHeadingReference]
}

enum VaultDerivedIndex {

    /// Reads each file once, preferring `overrides` (open editors) over disk.
    static func build(files: [VaultFile], overrides: [String: String]) -> VaultDerivedSnapshot {
        var entries: [(file: VaultFile, text: String)] = []
        entries.reserveCapacity(files.count)

        for file in files {
            let key = file.url.standardizedFileURL.path
            if let override = overrides[key] {
                entries.append((file, override))
                continue
            }
            guard !isTooLarge(file.url), let text = read(file.url) else { continue }
            entries.append((file, text))
        }
        return build(entries: entries)
    }

    /// Pure build used by tests and by `build(files:overrides:)`.
    static func build(entries: [(file: VaultFile, text: String)]) -> VaultDerivedSnapshot {
        var aliases: [String: URL] = [:]
        var tasks: [VaultTask] = []

        for entry in entries {
            registerAliases(for: entry.file, text: entry.text, into: &aliases)
            for task in VaultTaskIndex.tasks(in: entry.text) where !task.checked {
                tasks.append(
                    VaultTask(
                        sourceURL: entry.file.url,
                        relativePath: entry.file.relativePath,
                        sourceTitle: entry.file.title,
                        line: task.line,
                        text: task.text
                    )
                )
            }
        }

        var references: [VaultHeadingReference] = []
        for entry in entries {
            references.append(contentsOf: HeadingBacklinkIndex.references(
                in: entry.text,
                sourceURL: entry.file.url,
                sourceTitle: entry.file.title,
                aliases: aliases
            ))
        }

        tasks.sort { lhs, rhs in
            let order = lhs.sourceTitle.localizedStandardCompare(rhs.sourceTitle)
            if order != .orderedSame { return order == .orderedAscending }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.text < rhs.text
        }

        return VaultDerivedSnapshot(openTasks: tasks, headingReferences: references)
    }

    private static func registerAliases(
        for file: VaultFile,
        text: String,
        into aliases: inout [String: URL]
    ) {
        var keys = [
            file.title.lowercased(),
            strippingExtension(file.relativePath).lowercased()
        ]
        if let frontmatter = MarkdownFrontmatterParser.parse(text) {
            for name in ["aliases", "alias"] {
                guard let raw = frontmatter.field(named: name) else { continue }
                let values = raw.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                keys.append(contentsOf: values.map { $0.lowercased() })
            }
        }
        for key in keys where !key.isEmpty {
            if aliases[key] == nil {
                aliases[key] = file.url
            }
        }
    }

    private static func strippingExtension(_ path: String) -> String {
        let lowered = path.lowercased()
        for ext in [".md", ".markdown"] where lowered.hasSuffix(ext) {
            return String(path.dropLast(ext.count))
        }
        return path
    }

    private static func read(_ url: URL) -> String? {
        var encoding: String.Encoding = .utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) {
            return text
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func isTooLarge(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { return false }
        return size > 2 * 1024 * 1024
    }
}
