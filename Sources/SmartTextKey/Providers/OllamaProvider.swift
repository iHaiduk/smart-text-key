import Foundation

struct OllamaProviderClient: AIProviderClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(
        config: APIConfig,
        action: PromptAction,
        finalPrompt: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        var request = ProviderHTTP.request(
            url: try ProviderHTTP.url(baseURL: nativeBaseURL(config.apiBaseURL), defaultBaseURL: APIProvider.ollama.defaultBaseURL, path: "api/chat"),
            apiKey: config.apiKey
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: action.systemPrompt),
                .init(role: "user", content: finalPrompt)
            ],
            stream: onChunk != nil
        ))

        if let onChunk {
            return try await streamCompletion(request: request, onChunk: onChunk)
        }

        let (data, response) = try await ProviderHTTP.data(for: request, session: session)
        try ProviderHTTP.validate(response, data: data)
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        guard let content = decoded.message?.content, !content.isEmpty else {
            throw AIError.emptyChoice
        }
        return content
    }

    func verifyConnection(baseURL: String, apiKey: String) async throws -> String {
        var request = ProviderHTTP.request(
            url: try ProviderHTTP.url(baseURL: nativeBaseURL(baseURL), defaultBaseURL: APIProvider.ollama.defaultBaseURL, path: "api/tags"),
            apiKey: apiKey
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0

        let (data, response) = try await ProviderHTTP.data(for: request, session: session)
        try ProviderHTTP.validate(response, data: data)
        return ProviderHTTP.connectedMessage(from: decodeModels(data))
    }

    func fetchAvailableModels(baseURL: String, apiKey: String) async -> [String] {
        guard let url = try? ProviderHTTP.url(baseURL: nativeBaseURL(baseURL), defaultBaseURL: APIProvider.ollama.defaultBaseURL, path: "api/tags") else {
            return []
        }
        var request = ProviderHTTP.request(url: url, apiKey: apiKey)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0

        guard let (data, response) = try? await ProviderHTTP.data(for: request, session: session), response.statusCode == 200 else {
            return []
        }
        return decodeModels(data)
    }

    private func nativeBaseURL(_ baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/v1") {
            base.removeLast(3)
        } else if base.hasSuffix("/v1/") {
            base.removeLast(4)
        }
        return base
    }

    private func streamCompletion(request: URLRequest, onChunk: @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await ProviderHTTP.bytes(for: request, session: session)
        try ProviderHTTP.validate(response)

        var fullResponseText = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) else {
                continue
            }

            if let chunk = decoded.message?.content, !chunk.isEmpty {
                fullResponseText += chunk
                onChunk(chunk)
            }

            if decoded.done == true {
                break
            }
        }

        return fullResponseText
    }

    private func decodeModels(_ data: Data) -> [String] {
        guard let list = try? JSONDecoder().decode(OllamaModelList.self, from: data) else {
            return []
        }
        return list.models.map(\.name).sorted()
    }
}
