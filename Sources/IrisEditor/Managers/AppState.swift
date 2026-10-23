import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var document: EditorDocument = EditorDocument()
    @Published var settings: EditorSettings = EditorSettings.load()
    
    @Published var showFindReplace: Bool = false {
        didSet {
            if showFindReplace { showGoToLine = false }
        }
    }
    @Published var showGoToLine: Bool = false {
        didSet {
            if showGoToLine { showFindReplace = false }
        }
    }
    @Published var showSettings: Bool = false
    
    @Published var findText: String = ""
    @Published var replaceText: String = ""
    @Published var findMatchIndex: Int = 0
    @Published private(set) var findMatches: [Range<String.Index>] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Auto-save settings
        $settings
            .dropFirst()
            .sink { [weak self] newSettings in
                self?.saveSettings(newSettings)
            }
            .store(in: &cancellables)
        
        // Recompute find matches when find text or document text changes
        // Switch on document identity changes to subscribe to the new document's text
        Publishers.CombineLatest3(
            $findText,
            $document.flatMap { doc in
                doc.$text.map { text in (doc, text) }
            },
            $document
        )
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] findText, docTextPair, _ in
            self?.updateFindMatches(findText: findText, text: docTextPair.1)
        }
        .store(in: &cancellables)
    }
    
    private func updateFindMatches(findText: String, text: String) {
        findMatches = findAllOccurrences(in: text, query: findText)
        findMatchIndex = findMatches.isEmpty ? 0 : min(findMatchIndex, findMatches.count - 1)
        
        // Convert to NSRange and post for highlighting
        let nsRanges = findMatches.map { range in
            NSRange(range, in: text)
        }
        NotificationCenter.default.post(
            name: .findHighlight,
            object: nil,
            userInfo: ["ranges": nsRanges]
        )
    }
    
    // MARK: - Document Operations
    
    func newDocument() {
        document = EditorDocument()
        findText = ""
        replaceText = ""
    }
    
    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text, .plainText]
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                document = EditorDocument()
                document.text = content
                document.fileURL = url
                document.isDirty = false
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
    
    func saveDocument() {
        if let fileURL = document.fileURL {
            save(to: fileURL)
        } else {
            saveDocumentAs()
        }
    }
    
    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text, .plainText]
        panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? "Untitled.txt"
        
        if panel.runModal() == .OK, let url = panel.url {
            save(to: url)
        }
    }
    
    private func save(to url: URL) {
        do {
            try document.text.write(to: url, atomically: true, encoding: .utf8)
            document.fileURL = url
            document.isDirty = false
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
    
    // MARK: - Find/Replace
    
    func performFind(forward: Bool = true) {
        guard !findText.isEmpty, !findMatches.isEmpty else { return }
        
        if forward {
            findMatchIndex = (findMatchIndex + 1) % findMatches.count
        } else {
            findMatchIndex = (findMatchIndex - 1 + findMatches.count) % findMatches.count
        }
    }
    
    func findAllOccurrences(in text: String, query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
            if searchRange.lowerBound >= text.endIndex { break }
        }
        return ranges
    }
    
    func replaceCurrent() {
        guard !findMatches.isEmpty, findMatchIndex < findMatches.count else { return }
        let range = findMatches[findMatchIndex]
        document.text.replaceSubrange(range, with: replaceText)
        document.isDirty = true
    }
    
    func replaceAll() {
        guard !findText.isEmpty else { return }
        document.text = document.text.replacingOccurrences(
            of: findText, with: replaceText, options: .caseInsensitive
        )
        document.isDirty = true
    }
    
    // MARK: - Go to Line
    
    func goToLine(_ lineNumber: Int) {
        guard lineNumber > 0 && lineNumber <= document.lineCount else { return }
        
        NotificationCenter.default.post(
            name: .goToLine,
            object: nil,
            userInfo: ["line": lineNumber]
        )
    }
    
    // MARK: - Settings Persistence
    
    private func saveSettings(_ newSettings: EditorSettings) {
        if let data = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(data, forKey: "IrisEditor.Settings")
        }
    }
}

extension Notification.Name {
    static let goToLine = Notification.Name("IrisEditor.goToLine")
    static let findHighlight = Notification.Name("IrisEditor.findHighlight")
}
