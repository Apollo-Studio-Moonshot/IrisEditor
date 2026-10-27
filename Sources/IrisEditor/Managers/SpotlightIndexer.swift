import Foundation
import UniformTypeIdentifiers

#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

/// Publishes vault notes to Spotlight so they appear in system search results.
///
/// Indexing is best-effort: sandboxing or missing entitlements can make the index
/// unavailable, so failures are ignored and never block the editor.
enum SpotlightIndexer {
    static let domainIdentifier = "com.iriseditor.vault"

    static func index(files: [VaultFile]) {
        #if canImport(CoreSpotlight)
        let items: [CSSearchableItem] = files.prefix(800).compactMap { file in
            let attributes = CSSearchableItemAttributeSet(
                contentType: UTType(filenameExtension: "md") ?? .plainText
            )
            attributes.title = file.title
            attributes.contentDescription = file.relativePath
            attributes.contentModificationDate = file.modified
            attributes.keywords = ["Iris", "Markdown"]
            return CSSearchableItem(
                uniqueIdentifier: file.url.path,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }

        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
        #endif
    }

    static func removeAll() {
        #if canImport(CoreSpotlight)
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { _ in }
        #endif
    }
}
