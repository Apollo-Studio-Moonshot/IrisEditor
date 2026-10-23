import Foundation

@MainActor
class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()
    
    @Published var text: String = ""
    @Published var fileURL: URL? = nil
    @Published var isDirty: Bool = false
    
    var displayName: String {
        if let fileURL = fileURL {
            return fileURL.lastPathComponent
        }
        return "Untitled"
    }
    
    var wordCount: Int {
        let words = text.split { $0 == " " || $0.isNewline }
        return words.filter { !$0.isEmpty }.count
    }
    
    var characterCount: Int {
        text.count
    }
    
    var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }
    
    var fileSizeDescription: String {
        if let fileURL = fileURL, let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? Int64 {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        let data = text.data(using: .utf8) ?? Data()
        return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
    
    var cursorLine: Int = 1
    var cursorColumn: Int = 1
}
