import Combine
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writing assistant that runs either on-device with Apple Intelligence
/// (Foundation Models) or against a linked remote provider (DeepSeek, OpenAI,
/// Anthropic, or a custom OpenAI-compatible endpoint).
///
/// The active backend comes from `configuration`, which `AppState` keeps in sync
/// with Settings. Generation methods throw `AIUnavailableError` when the selected
/// backend is not usable.
@MainActor
final class AIAssistant: ObservableObject {
    static let shared = AIAssistant()

    enum Capability: String, Sendable {
        case inlineCompletion
        case rewrite
        case summarize
        case titleTags
    }

    struct AIUnavailableError: LocalizedError {
        let message: String

        init(message: String = "Apple Intelligence is not available on this Mac. Enable it in System Settings › Apple Intelligence & Siri.") {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    private enum AvailabilityStatus: Sendable {
        case available
        case unavailable(reason: String)
    }

    private let localStatus: AvailabilityStatus

    /// Selected provider plus its endpoint, model, and key. Kept in sync by `AppState`.
    @Published private(set) var configuration = AIProviderConfiguration()

    /// True when the selected provider can be used right now.
    var isAvailable: Bool {
        if configuration.provider.isRemote {
            return configuration.isConfigured
        }
        if case .available = localStatus { return true }
        return false
    }

    /// Human-readable status for Settings/empty states.
    var availabilityDescription: String {
        if configuration.provider.isRemote {
            guard configuration.isConfigured else {
                return "Add an API key for \(configuration.provider.title) in Settings › AI Provider."
            }
            return "\(configuration.provider.title) · \(configuration.effectiveModel)"
        }

        switch localStatus {
        case .available:
            return "Apple Intelligence is available on this Mac."
        case .unavailable(let reason):
            return reason
        }
    }

    private init() {
        localStatus = AIAssistant.resolveAvailability()
    }

    /// Applies the provider chosen in Settings.
    func apply(configuration: AIProviderConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
    }

    private func unavailableError() -> AIUnavailableError {
        if configuration.provider.isRemote {
            return AIUnavailableError(
                message: "Add an API key for \(configuration.provider.title) in Settings › AI Provider."
            )
        }
        if case .unavailable(let reason) = localStatus {
            return AIUnavailableError(message: reason)
        }
        return AIUnavailableError()
    }

    // MARK: - Generation

    /// Continue the sentence at the caret. Returns at most `maxWords` words; empty when unavailable.
    func complete(before: String, after: String, maxWords: Int = 12) async throws -> String {
        guard maxWords > 0 else { return "" }
        guard isAvailable else { throw unavailableError() }

        let context = Self.caretContext(before: before, after: after)
        let prompt = """
        Continue the text exactly at the <cursor> marker. Reply with only the words \
        that follow, using at most \(maxWords) words.

        <before_cursor>
        \(context.before)
        </before_cursor>
        <cursor>
        <after_cursor>
        \(context.after)
        </after_cursor>
        """

        if configuration.provider.isRemote {
            let response = try await AIProviderClient.respond(
                configuration: configuration,
                system: Self.completionInstructions,
                prompt: prompt
            )
            return Self.sanitizedCompletion(response, maxWords: maxWords)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: Self.completionInstructions)
            let response = try await session.respond(to: prompt)
            return Self.sanitizedCompletion(response.content, maxWords: maxWords)
        }
        #endif

        throw unavailableError()
    }

    /// Rewrite selected text according to a plain-English instruction.
    func rewrite(_ text: String, instruction: String?) async throws -> String {
        guard isAvailable else { throw unavailableError() }

        let directive = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = (directive?.isEmpty == false)
            ? "Rewrite the text using this instruction: \(directive!)"
            : "Rewrite the text to be clearer and more concise."
        let prompt = """
        \(task)
        Return only the rewritten text, without explanations or surrounding quotes.

        \(text)
        """

        let result: String
        if configuration.provider.isRemote {
            result = try await AIProviderClient.respond(
                configuration: configuration,
                system: Self.rewriteInstructions,
                prompt: prompt
            )
        } else {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let session = LanguageModelSession(instructions: Self.rewriteInstructions)
                let response = try await session.respond(to: prompt)
                result = response.content
            } else {
                throw unavailableError()
            }
            #else
            throw unavailableError()
            #endif
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    /// Summarize a whole document.
    func summarize(_ text: String) async throws -> String {
        guard isAvailable else { throw unavailableError() }

        let prompt = """
        Summarize the following document in at most five sentences. \
        Return only the summary, without a heading, quotes, or commentary.

        \(text)
        """

        let result: String
        if configuration.provider.isRemote {
            result = try await AIProviderClient.respond(
                configuration: configuration,
                system: Self.summaryInstructions,
                prompt: prompt
            )
        } else {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let session = LanguageModelSession(instructions: Self.summaryInstructions)
                let response = try await session.respond(to: prompt)
                result = response.content
            } else {
                throw unavailableError()
            }
            #else
            throw unavailableError()
            #endif
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate a title and up to 5 tags.
    func titleAndTags(for text: String) async throws -> (title: String, tags: [String]) {
        guard isAvailable else { throw unavailableError() }

        let prompt = """
        Create a title of at most eight words and up to five lowercase tags for \
        the document below. Reply with only JSON in this exact shape:
        {"title": "...", "tags": ["...", "..."]}

        Document:
        \(text)
        """

        let result: String
        if configuration.provider.isRemote {
            result = try await AIProviderClient.respond(
                configuration: configuration,
                system: Self.metadataInstructions,
                prompt: prompt
            )
        } else {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let session = LanguageModelSession(instructions: Self.metadataInstructions)
                let response = try await session.respond(to: prompt)
                result = response.content
            } else {
                throw unavailableError()
            }
            #else
            throw unavailableError()
            #endif
        }

        return Self.parseTitleAndTags(result, fallbackText: text)
    }

    // MARK: - Prompt instructions

    private static let completionInstructions = """
    You are a concise writing assistant inside a Markdown editor. \
    Reply with only the continuation of the user's text, without quotes, \
    labels, or explanation, on a single line.
    """

    private static let rewriteInstructions = """
    You are a concise writing assistant inside a Markdown editor. \
    Reply with only the requested text, preserving Markdown formatting where possible.
    """

    private static let summaryInstructions = """
    You are a concise writing assistant inside a Markdown editor. \
    Reply with only the requested summary as plain Markdown-compatible prose.
    """

    private static let metadataInstructions = """
    You are a concise writing assistant inside a Markdown editor. \
    Reply with only the requested JSON object, without prose or code fences.
    """

    // MARK: - Availability

    private static func resolveAvailability() -> AvailabilityStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable(reason: "This Mac does not support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: "Apple Intelligence is turned off. Enable it in System Settings › Apple Intelligence & Siri.")
                case .modelNotReady:
                    return .unavailable(reason: "Apple Intelligence is still preparing the on-device model. Try again shortly.")
                @unknown default:
                    return .unavailable(reason: "Apple Intelligence is currently unavailable on this Mac.")
                }
            }
        }
        #endif

        return .unavailable(reason: "Apple Intelligence requires macOS 26 or later.")
    }

    // MARK: - Helpers

    private static let contextLimit = 4000

    private static func caretContext(before: String, after: String) -> (before: String, after: String) {
        // Keep the end of the preceding text and the start of the following text
        // so the prompt stays close to the caret while remaining bounded.
        let beforeBudget = contextLimit * 3 / 4
        let afterBudget = contextLimit - beforeBudget
        return (
            String(before.suffix(beforeBudget)),
            String(after.prefix(afterBudget))
        )
    }

    private static func sanitizedCompletion(_ raw: String, maxWords: Int) -> String {
        guard maxWords > 0 else { return "" }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let firstLine = trimmed.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? trimmed
        let words = firstLine.split(whereSeparator: { $0.isWhitespace })
        return words.prefix(maxWords).joined(separator: " ")
    }

    private static func parseTitleAndTags(
        _ raw: String,
        fallbackText: String
    ) -> (title: String, tags: [String]) {
        let fallback = fallbackTitle(for: fallbackText)

        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return (fallback, [])
        }

        let parsedTitle = (object["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (parsedTitle?.isEmpty == false) ? parsedTitle! : fallback

        var seen = Set<String>()
        var tags: [String] = []
        for case let tag as String in (object["tags"] as? [Any] ?? []) {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            tags.append(normalized)
            if tags.count == 5 { break }
        }

        return (title, tags)
    }

    private static func fallbackTitle(for text: String) -> String {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let cleaned = line
                .trimmingCharacters(in: .whitespaces)
                .drop(while: { "#>*-_".contains($0) || $0 == " " })
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(80))
            }
        }
        return "Untitled"
    }
}
