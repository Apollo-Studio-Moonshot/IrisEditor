import Foundation
import Security

/// AI backend the writing assistant talks to.
enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleIntelligence
    case deepSeek
    case openAI
    case anthropic
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .deepSeek: return "DeepSeek"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .custom: return "Custom"
        }
    }

    /// Providers that require an API key and network access.
    var isRemote: Bool { self != .appleIntelligence }

    var defaultBaseURL: String {
        switch self {
        case .appleIntelligence, .custom: return ""
        case .deepSeek: return "https://api.deepseek.com"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .appleIntelligence, .custom: return ""
        case .deepSeek: return "deepseek-chat"
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-5"
        }
    }
}

/// Persisted provider choice. The API key is kept out of the Codable payload and
/// stored separately in the macOS Keychain by `AICredentialStore`.
struct AIProviderConfiguration: Codable, Equatable, Sendable {
    var provider: AIProvider = .appleIntelligence
    var apiKey: String = ""
    var model: String = ""
    var baseURL: String = ""

    var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultBaseURL : trimmed
    }

    var effectiveAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a remote provider has everything needed to make a request.
    var isConfigured: Bool {
        guard provider.isRemote else { return false }
        return !effectiveAPIKey.isEmpty
            && !effectiveModel.isEmpty
            && URL(string: effectiveBaseURL) != nil
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case provider, model, baseURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try container.decodeIfPresent(String.self, forKey: .provider) {
            provider = AIProvider(rawValue: raw) ?? .appleIntelligence
        }
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(baseURL, forKey: .baseURL)
    }
}

/// Stores the provider API key in the login Keychain instead of UserDefaults.
enum AICredentialStore {
    private static let service = "com.apollostudiomoonshot.IrisEditor"
    private static let account = "AIProviderAPIKey"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func loadAPIKey() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func saveAPIKey(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
