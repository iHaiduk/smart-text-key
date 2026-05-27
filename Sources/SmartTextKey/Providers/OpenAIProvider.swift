import Foundation

struct OpenAICompatibleProviderClient: AIProviderClient {
    let defaultBaseURL: String
    let session: URLSession

    init(defaultBaseURL: String, session: URLSession = .shared) {
        self.defaultBaseURL = defaultBaseURL
        self.session = session
    }

    func complete(
        config: APIConfig,
        action: PromptAction,
        finalPrompt: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        var request = ProviderHTTP.request(
            url: try ProviderHTTP.url(baseURL: config.apiBaseURL, defaultBaseURL: defaultBaseURL, path: "chat/completions"),
            apiKey: config.apiKey
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: action.systemPrompt),
                .init(role: "user", content: finalPrompt)
            ],
            n: 1,
            stream: onChunk != nil ? true : nil
        ))

        if let onChunk {
            return try await streamCompletion(request: request, onChunk: onChunk)
        }

        let (data, response) = try await ProviderHTTP.data(for: request, session: session)
        try ProviderHTTP.validate(response, data: data)
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let assistantMessage = chatResponse.choices.first?.message.content else {
            throw AIError.emptyChoice
        }

        return assistantMessage
    }

    func verifyConnection(baseURL: String, apiKey: String) async throws -> String {
        var request = ProviderHTTP.request(
            url: try ProviderHTTP.url(baseURL: baseURL, defaultBaseURL: defaultBaseURL, path: "models"),
            apiKey: apiKey
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0

        let (data, response) = try await ProviderHTTP.data(for: request, session: session)
        if response.statusCode == 404 {
            return "Connected (Server reached)"
        }
        try ProviderHTTP.validate(response, data: data)
        return ProviderHTTP.connectedMessage(from: decodeOpenAIModels(data))
    }

    func fetchAvailableModels(baseURL: String, apiKey: String) async -> [String] {
        guard let url = try? ProviderHTTP.url(baseURL: baseURL, defaultBaseURL: defaultBaseURL, path: "models") else {
            return []
        }
        var request = ProviderHTTP.request(url: url, apiKey: apiKey)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0

        guard let (data, response) = try? await ProviderHTTP.data(for: request, session: session), response.statusCode == 200 else {
            return []
        }
        return decodeOpenAIModels(data)
    }

    private func streamCompletion(request: URLRequest, onChunk: @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await ProviderHTTP.bytes(for: request, session: session)
        try ProviderHTTP.validate(response)

        var fullResponseText = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed == "data: [DONE]" {
                break
            }

            guard trimmed.hasPrefix("data: ") else { continue }

            let jsonString = String(trimmed.dropFirst(6))
            guard let jsonData = jsonString.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(StreamResponse.self, from: jsonData),
                  let chunk = decoded.choices.first?.delta.content else {
                continue
            }

            fullResponseText += chunk
            onChunk(chunk)
        }

        return fullResponseText
    }

    private func decodeOpenAIModels(_ data: Data) -> [String] {
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            return []
        }
        return list.data.map(\.id).sorted()
    }
}
