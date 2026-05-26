import AppKit
import Carbon
import Foundation

public enum AIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case apiError(Int, String)
    case emptyChoice

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API Base URL configuration."
        case .networkError(let error):
            return "Network request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "The server returned an invalid or unparsable response."
        case .apiError(let statusCode, let message):
            return "AI Server returned error (Status \(statusCode)): \(message)"
        case .emptyChoice:
            return "AI returned an empty response choice."
        }
    }
}

public final class AIService: AIClientProtocol, Sendable {
    public static let shared = AIService()

    private init() {}

    /// Processes a PromptAction by substituting template tags,
    /// executing HTTP requests with streaming support,
    /// and offering failover fallbacks.
    @MainActor
    public func process(
        action: PromptAction,
        capturedText: String,
        originalClipboardText: String,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)

        var finalPrompt = action.template.replacingOccurrences(of: "{{TEXT}}", with: capturedText)
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{CLIPBOARD}}", with: originalClipboardText)
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{DATE}}", with: dateStr)
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{CURRENT_APP}}", with: appName)

        let apiSettings = await AppSettings.shared
        let config: APIConfig
        if let boundId = action.apiConfigId,
           let boundConfig = await apiSettings.apiConfigs.first(where: { $0.id == boundId }) {
            config = boundConfig
        } else {
            config = await apiSettings.activeConfig
        }

        var resultText: String
        do {
            resultText = try await executeRequest(config: config, action: action, finalPrompt: finalPrompt, onChunk: onChunk)
        } catch {
            if let fallbackId = config.fallbackConfigId,
               let fallbackConfig = await apiSettings.apiConfigs.first(where: { $0.id == fallbackId }) {
                print("Smart Text Key [AIService]: Primary API failed. Retrying with fallback: [\(fallbackConfig.name)]")
                SoundManager.shared.play(.failure)
                try await Task.sleep(for: .milliseconds(400))
                resultText = try await executeRequest(config: fallbackConfig, action: action, finalPrompt: finalPrompt, onChunk: onChunk)
            } else {
                throw error
            }
        }

        if let suffix = action.responseSuffix, !suffix.isEmpty {
            resultText += suffix
        }

        return resultText
    }

    private func executeRequest(
        config: APIConfig,
        action: PromptAction,
        finalPrompt: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let provider = providerClient(for: config.providerId)
        let text = try await provider.complete(config: config, action: action, finalPrompt: finalPrompt, onChunk: onChunk)
        return cleanThinkingProcess(text, finalPrompt: finalPrompt)
    }

    /// Strips thinking blocks (e.g., <think>...</think> or unclosed <think> blocks)
    /// and dynamically cleans out duplicate echoed prompt templates returned by local agentic LLMs.
    private func cleanThinkingProcess(_ text: String, finalPrompt: String) -> String {
        var cleaned = text

        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        if let regex = try? NSRegularExpression(pattern: "<thought>[\\s\\S]*?</thought>", options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        if let openThinkRange = cleaned.range(of: "<think>") {
            cleaned = String(cleaned[..<openThinkRange.lowerBound])
        }
        if let openThoughtRange = cleaned.range(of: "<thought>") {
            cleaned = String(cleaned[..<openThoughtRange.lowerBound])
        }

        let promptLines = finalPrompt.components(separatedBy: .newlines)
        if let firstSignificantLine = promptLines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let separator = firstSignificantLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if !separator.isEmpty && separator.count > 3 {
                let parts = cleaned.components(separatedBy: separator)
                if parts.count > 2 {
                    var lastValidSegment = ""
                    for part in parts.reversed() {
                        let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)

                        if !trimmedPart.isEmpty && !trimmedPart.contains("[") && !trimmedPart.contains("]") {
                            lastValidSegment = separator + "\n" + part
                            break
                        }
                    }
                    if !lastValidSegment.isEmpty {
                        cleaned = lastValidSegment
                    }
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Verifies the API connection using the selected provider strategy.
    public func verifyConnection(
        baseURL: String,
        apiKey: String,
        providerId: String = APIProvider.openAICompatible.id
    ) async throws -> String {
        try await providerClient(for: providerId).verifyConnection(baseURL: baseURL, apiKey: apiKey)
    }

    /// Fetches the list of model IDs available from the selected provider.
    public func fetchAvailableModels(
        baseURL: String,
        apiKey: String,
        providerId: String = APIProvider.openAICompatible.id
    ) async -> [String] {
        await providerClient(for: providerId).fetchAvailableModels(baseURL: baseURL, apiKey: apiKey)
    }

    private func providerClient(for providerId: String) -> AIProviderClient {
        switch APIProvider.normalizedId(providerId) {
        case APIProvider.ollama.id:
            return OllamaProviderClient()
        case APIProvider.anthropic.id:
            return AnthropicProviderClient()
        case APIProvider.deepSeek.id:
            return OpenAICompatibleProviderClient(defaultBaseURL: APIProvider.deepSeek.defaultBaseURL)
        default:
            return OpenAICompatibleProviderClient(defaultBaseURL: APIProvider.openAICompatible.defaultBaseURL)
        }
    }
}

private protocol AIProviderClient: Sendable {
    func complete(
        config: APIConfig,
        action: PromptAction,
        finalPrompt: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String

    func verifyConnection(baseURL: String, apiKey: String) async throws -> String
    func fetchAvailableModels(baseURL: String, apiKey: String) async -> [String]
}

private struct ProviderHTTP {
    static func url(baseURL: String, defaultBaseURL: String, path: String) throws -> URL {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = defaultBaseURL
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let url = URL(string: "\(base)/\(path)") else {
            throw AIError.invalidURL
        }
        return url
    }

    static func request(url: URL, apiKey: String, authorizationHeader: String = "Authorization") -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanApiKey.isEmpty else {
            return request
        }

        if authorizationHeader == "Authorization" {
            request.setValue("Bearer \(cleanApiKey)", forHTTPHeaderField: authorizationHeader)
        } else {
            request.setValue(cleanApiKey, forHTTPHeaderField: authorizationHeader)
        }

        return request
    }

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(error)
        }
    }

    static func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            return (bytes, httpResponse)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(error)
        }
    }

    static func validate(_ response: HTTPURLResponse, data: Data? = nil) throws {
        guard (200...299).contains(response.statusCode) else {
            let details = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP status \(response.statusCode)"
            throw AIError.apiError(response.statusCode, details)
        }
    }

    static func connectedMessage(from ids: [String]) -> String {
        guard let example = ids.first else {
            return "Connected (Online)"
        }
        return "Connected (\(ids.count) models: e.g. \(example))"
    }
}

private struct OpenAICompatibleProviderClient: AIProviderClient {
    let defaultBaseURL: String

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

        let (data, response) = try await ProviderHTTP.data(for: request)
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

        let (data, response) = try await ProviderHTTP.data(for: request)
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

        guard let (data, response) = try? await ProviderHTTP.data(for: request), response.statusCode == 200 else {
            return []
        }
        return decodeOpenAIModels(data)
    }

    private func streamCompletion(request: URLRequest, onChunk: @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await ProviderHTTP.bytes(for: request)
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

private struct OllamaProviderClient: AIProviderClient {
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

        let (data, response) = try await ProviderHTTP.data(for: request)
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

        let (data, response) = try await ProviderHTTP.data(for: request)
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

        guard let (data, response) = try? await ProviderHTTP.data(for: request), response.statusCode == 200 else {
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
        let (bytes, response) = try await ProviderHTTP.bytes(for: request)
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

private struct AnthropicProviderClient: AIProviderClient {
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

        let (data, response) = try await ProviderHTTP.data(for: request)
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

        let (data, response) = try await ProviderHTTP.data(for: request)
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

        guard let (data, response) = try? await ProviderHTTP.data(for: request), response.statusCode == 200 else {
            return fallbackModels
        }
        let models = decodeModels(data)
        return models.isEmpty ? fallbackModels : models
    }

    private func streamCompletion(request: URLRequest, onChunk: @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await ProviderHTTP.bytes(for: request)
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

private struct ChatCompletionRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let n: Int?
    let stream: Bool?
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String
        }
        let message: Message
    }

    let choices: [Choice]
}

private struct StreamResponse: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

private struct ModelList: Codable {
    struct ModelInfo: Codable {
        let id: String
    }
    let data: [ModelInfo]
}

private struct OllamaChatRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct OllamaChatResponse: Codable {
    struct Message: Codable {
        let content: String
    }

    let message: Message?
    let done: Bool?
}

private struct OllamaModelList: Codable {
    struct Model: Codable {
        let name: String
    }

    let models: [Model]
}

private struct AnthropicMessageRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let system: String
    let messages: [Message]
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct AnthropicMessageResponse: Codable {
    struct ContentBlock: Codable {
        let type: String?
        let text: String?
    }

    let content: [ContentBlock]
}

private struct AnthropicStreamResponse: Codable {
    struct Delta: Codable {
        let type: String?
        let text: String?
    }

    let type: String
    let delta: Delta?
}
