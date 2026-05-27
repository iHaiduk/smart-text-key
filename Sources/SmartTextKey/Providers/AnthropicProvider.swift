import Foundation

struct AnthropicProviderClient: AIProviderClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private let version = "2023-06-01"
    private let fallbackModels = [
        "claude-3-5-sonnet-latest",
        "claude-3-5-haiku-latest",
        "claude-3-opus-latest",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307"
    ]

    func complete(
        config: APIConfig,
        action: PromptAction,
        finalPrompt: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        var request = ProviderHTTP.request(
            url: try ProviderHTTP.url(baseURL: config.apiBaseURL, defaultBaseURL: APIProvider.anthropic.defaultBaseURL, path: "messages"),
            apiKey: config.apiKey,
            authorizationHeader: "x-api-key"
        )
        request.httpMethod = "POST"
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(AnthropicMessageRequest(
            model: config.modelName,
            system: action.systemPrompt,
            messages: [.init(role: "user", content: finalPrompt)],
            maxTokens: 4096,
            stream: onChunk != nil
        ))

        if let onChunk {
            return try await streamCompletion(request: request, onChunk: onChunk)
        }

        let (data, response) = try await ProviderHTTP.data(for: request, session: session)
        try ProviderHTTP.validate(response, data: data)
        let decoded = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        let text = decoded.content.compactMap(\.text).joined()
        guard !text.isEmpty else {
            throw AIError.emptyChoice
        }
        return text
    }

    func verifyConnection(baseURL: String, apiKey: String) async throws -> String {
        var request = ProviderHTTP.request(
            url: try ProviderHTTP.url(baseURL: baseURL, defaultBaseURL: APIProvider.anthropic.defaultBaseURL, path: "models"),
            apiKey: apiKey,
            authorizationHeader: "x-api-key"
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        request.setValue(version, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await ProviderHTTP.data(for: request, session: session)
        if response.statusCode == 404 {
            return ProviderHTTP.connectedMessage(from: fallbackModels)
        }
        try ProviderHTTP.validate(response, data: data)
        let models = decodeModels(data)
        return ProviderHTTP.connectedMessage(from: models.isEmpty ? fallbackModels : models)
    }

    func fetchAvailableModels(baseURL: String, apiKey: String) async -> [String] {
        guard let url = try? ProviderHTTP.url(baseURL: baseURL, defaultBaseURL: APIProvider.anthropic.defaultBaseURL, path: "models") else {
            return fallbackModels
        }
        var request = ProviderHTTP.request(url: url, apiKey: apiKey, authorizationHeader: "x-api-key")
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        request.setValue(version, forHTTPHeaderField: "anthropic-version")

        guard let (data, response) = try? await ProviderHTTP.data(for: request, session: session), response.statusCode == 200 else {
            return fallbackModels
        }
        let models = decodeModels(data)
        return models.isEmpty ? fallbackModels : models
    }

    private func streamCompletion(request: URLRequest, onChunk: @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await ProviderHTTP.bytes(for: request, session: session)
        try ProviderHTTP.validate(response)

        var fullResponseText = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }

            let jsonString = String(trimmed.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AnthropicStreamResponse.self, from: data) else {
                continue
            }

            if decoded.type == "message_stop" {
                break
            }

            guard let chunk = decoded.delta?.text, !chunk.isEmpty else {
                continue
            }

            fullResponseText += chunk
            onChunk(chunk)
        }

        return fullResponseText
    }

    private func decodeModels(_ data: Data) -> [String] {
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            return []
        }
        return list.data.map(\.id).sorted()
    }
}
