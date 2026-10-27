import Foundation

enum AIProviderClientError: LocalizedError {
    case missingConfiguration(String)
    case invalidBaseURL
    case requestFailed(status: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .invalidBaseURL:
            return "The provider base URL is not valid. Check it in Settings › AI Provider."
        case .requestFailed(let status, let message):
            return message.isEmpty
                ? "The AI provider returned HTTP \(status)."
                : "The AI provider returned HTTP \(status): \(message)"
        case .emptyResponse:
            return "The AI provider returned an empty response."
        }
    }
}

/// Minimal client for the supported remote chat APIs.
///
/// DeepSeek, OpenAI, and custom providers use the OpenAI-compatible
/// `/chat/completions` shape; Anthropic uses `/messages`.
enum AIProviderClient {
    static func respond(
        configuration: AIProviderConfiguration,
        system: String,
        prompt: String
    ) async throws -> String {
        guard configuration.provider.isRemote else {
            throw AIProviderClientError.missingConfiguration(
                "Choose an AI provider in Settings › AI Provider."
            )
        }
        guard configuration.isConfigured else {
            throw AIProviderClientError.missingConfiguration(
                "Add an API key for \(configuration.provider.title) in Settings › AI Provider."
            )
        }

        let isAnthropic = configuration.provider == .anthropic
        let path = isAnthropic ? "messages" : "chat/completions"
        guard let url = endpoint(base: configuration.effectiveBaseURL, path: path) else {
            throw AIProviderClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        if isAnthropic {
            request.setValue(configuration.effectiveAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": configuration.effectiveModel,
                "max_tokens": 2048,
                "system": system,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
        } else {
            request.setValue("Bearer \(configuration.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": configuration.effectiveModel,
                "temperature": 0.3,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": prompt]
                ]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderClientError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderClientError.requestFailed(
                status: http.statusCode,
                message: apiErrorMessage(from: data) ?? ""
            )
        }

        let text = try decodedText(from: data, anthropic: isAnthropic)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIProviderClientError.emptyResponse }
        return text
    }

    // MARK: - Endpoints

    /// Joins a base URL with an API path, accepting a full endpoint as the base too.
    private static func endpoint(base: String, path: String) -> URL? {
        var value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasSuffix("/" + path) {
            return URL(string: value)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value + "/" + path)
    }

    // MARK: - Response parsing

    private struct OpenAIResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct AnthropicResponse: Decodable {
        struct Block: Decodable {
            let type: String?
            let text: String?
        }
        let content: [Block]
    }

    private static func decodedText(from data: Data, anthropic: Bool) throws -> String {
        if anthropic {
            guard let response = try? JSONDecoder().decode(AnthropicResponse.self, from: data) else {
                throw AIProviderClientError.emptyResponse
            }
            let text = response.content
                .filter { $0.type == nil || $0.type == "text" }
                .compactMap(\.text)
                .joined()
            guard !text.isEmpty else { throw AIProviderClientError.emptyResponse }
            return text
        }

        guard let response = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
              let text = response.choices.first?.message.content else {
            throw AIProviderClientError.emptyResponse
        }
        return text
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}
