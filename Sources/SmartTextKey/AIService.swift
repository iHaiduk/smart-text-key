import Foundation
import AppKit

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

public final class AIService: Sendable {
    public static let shared = AIService()
    
    private init() {}
    
    /// Processes a PromptAction by substituting template tags,
    /// executing HTTP requests with Server-Sent Events (SSE) streaming support,
    /// and offering failover fallbacks.
    public func process(
        action: PromptAction,
        capturedText: String,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        // 1. Substitute variables on MainActor safely
        let clipboardText = await MainActor.run { NSPasteboard.general.string(forType: .string) ?? "" }
        let appName = await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App" }
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        
        var finalPrompt = action.template.replacingOccurrences(of: "{{TEXT}}", with: capturedText)
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{CLIPBOARD}}", with: clipboardText)
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{DATE}}", with: dateStr)
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{CURRENT_APP}}", with: appName)
        
        // 2. Fetch API configuration (action-specific or fallback to global active profile)
        let apiSettings = await AppSettings.shared
        let config: APIConfig
        if let boundId = action.apiConfigId,
           let boundConfig = await apiSettings.apiConfigs.first(where: { $0.id == boundId }) {
            config = boundConfig
        } else {
            config = await apiSettings.activeConfig
        }
        
        // 3. Execute with failover fallback support
        var resultText: String
        do {
            resultText = try await executeRequest(config: config, action: action, finalPrompt: finalPrompt, onChunk: onChunk)
        } catch {
            if let fallbackId = config.fallbackConfigId,
               let fallbackConfig = await apiSettings.apiConfigs.first(where: { $0.id == fallbackId }) {
                print("Smart Text Key [AIService]: Primary API failed. Retrying with fallback: [\(fallbackConfig.name)]")
                
                // Play warning sound on failover
                SoundManager.shared.play(.failure)
                
                // Wait slightly before retry to ensure server switch is clean
                try? await Task.sleep(for: .milliseconds(400))
                
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
        let baseURLString = config.apiBaseURL
        let apiKey = config.apiKey
        let modelName = config.modelName
        
        var cleanURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURLString.hasSuffix("/") {
            cleanURLString += "/"
        }
        cleanURLString += "chat/completions"
        
        guard let url = URL(string: cleanURLString) else {
            throw AIError.invalidURL
        }
        
        let requestPayload = ChatCompletionRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: action.systemPrompt),
                .init(role: "user", content: finalPrompt)
            ],
            n: 1,
            stream: onChunk != nil ? true : nil
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanApiKey.isEmpty {
            request.setValue("Bearer \(cleanApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(requestPayload)
        } catch {
            throw AIError.invalidResponse
        }
        
        if onChunk != nil {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AIError.apiError(httpResponse.statusCode, "Streaming failed with HTTP status \(httpResponse.statusCode)")
            }
            
            var fullResponseText = ""
            
            struct StreamChoice: Codable {
                struct Delta: Codable {
                    let content: String?
                }
                let delta: Delta
            }
            struct StreamResponse: Codable {
                let choices: [StreamChoice]
            }
            
            for try await line in bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                if trimmed == "data: [DONE]" {
                    break
                }
                
                if trimmed.hasPrefix("data: ") {
                    let jsonString = String(trimmed.dropFirst(6))
                    if let jsonData = jsonString.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(StreamResponse.self, from: jsonData),
                       let chunk = decoded.choices.first?.delta.content {
                        fullResponseText += chunk
                        onChunk?(chunk)
                    }
                }
            }
            
            let cleaned = cleanThinkingProcess(fullResponseText, finalPrompt: finalPrompt)
            return cleaned
        } else {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw AIError.networkError(error)
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorDetails = String(data: data, encoding: .utf8) ?? "No details available."
                    throw AIError.apiError(httpResponse.statusCode, errorDetails)
                }
            }
            
            let decoder = JSONDecoder()
            let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
            
            guard let assistantMessage = chatResponse.choices.first?.message.content else {
                throw AIError.emptyChoice
            }
            
            let cleanedMessage = cleanThinkingProcess(assistantMessage, finalPrompt: finalPrompt)
            return cleanedMessage
        }
    }
    
    /// Strips thinking blocks (e.g., <think>...</think> or unclosed <think> blocks)
    /// and dynamically cleans out duplicate echoed prompt templates returned by local agentic LLMs.
    private func cleanThinkingProcess(_ text: String, finalPrompt: String) -> String {
        var cleaned = text
        
        // 1. Remove complete <think>...</think> blocks including their contents (DeepSeek-R1 reasoning)
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // 2. Remove complete <thought>...</thought> blocks (Alternative reasoning tags)
        if let regex = try? NSRegularExpression(pattern: "<thought>[\\s\\S]*?</thought>", options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // 3. Fallback: If there is an unclosed <think> or <thought> tag (due to cutoff), strip everything after it
        if let openThinkRange = cleaned.range(of: "<think>") {
            cleaned = String(cleaned[..<openThinkRange.lowerBound])
        }
        if let openThoughtRange = cleaned.range(of: "<thought>") {
            cleaned = String(cleaned[..<openThoughtRange.lowerBound])
        }
        
        // 4. Dynamic completion echo / agent loop separator cleanser.
        // Strips repeated prompt headers without hardcoding any specific keywords.
        // It dynamically uses the first non-empty line of the sent prompt as the delimiter.
        let promptLines = finalPrompt.components(separatedBy: .newlines)
        if let firstSignificantLine = promptLines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let separator = firstSignificantLine.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check that the separator is significant and long enough
            if !separator.isEmpty && separator.count > 3 {
                let parts = cleaned.components(separatedBy: separator)
                if parts.count > 2 {
                    var lastValidSegment = ""
                    // Iterate in reverse to find the final completed agent turn response block
                    for part in parts.reversed() {
                        let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Ensure the segment is not empty and is not just an uncompleted prompt placeholder template
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
        
        // 5. Trim whitespaces and newlines
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Verifies the API connection by hitting <baseURL>/models.
    /// Enforces a 5-second timeout and decodes available models on success.
    public func verifyConnection(baseURL: String, apiKey: String) async throws -> String {
        var cleanURLString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURLString.hasSuffix("/") {
            cleanURLString += "/"
        }
        cleanURLString += "models"
        
        guard let url = URL(string: cleanURLString) else {
            throw AIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanApiKey.isEmpty {
            request.setValue("Bearer \(cleanApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let data: Data
        let response: URLResponse
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5.0
            config.timeoutIntervalForResource = 5.0
            let session = URLSession(configuration: config)
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        let statusCode = httpResponse.statusCode
        if statusCode != 200 {
            if statusCode == 401 || statusCode == 403 {
                throw AIError.apiError(statusCode, "Unauthorized (Invalid API Key)")
            } else if statusCode == 404 {
                // Endpoint responded but path not found (typical for some custom local servers)
                return "Connected (Server reached)"
            } else {
                let msg = String(data: data, encoding: .utf8)?.prefix(50) ?? "Server Error"
                throw AIError.apiError(statusCode, String(msg))
            }
        }
        
        // Parse models if returned
        struct ModelInfo: Codable {
            let id: String
        }
        struct ModelList: Codable {
            let data: [ModelInfo]
        }
        
        if let list = try? JSONDecoder().decode(ModelList.self, from: data), !list.data.isEmpty {
            let count = list.data.count
            let example = list.data[0].id
            return "Connected (\(count) models: e.g. \(example))"
        }
        
        return "Connected (Online)"
    }
    
    /// Fetches the list of model IDs available from the server dynamically.
    /// Supports standard OpenAI/v1/models and Ollama's direct /api/tags endpoints.
    public func fetchAvailableModels(baseURL: String, apiKey: String) async -> [String] {
        var cleanURLString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURLString.hasSuffix("/") {
            cleanURLString += "/"
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        let session = URLSession(configuration: config)
        
        // 1. Try standard OpenAI /models endpoint
        if let openaiURL = URL(string: cleanURLString + "models") {
            var request = URLRequest(url: openaiURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 4.0
            
            let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanApiKey.isEmpty {
                request.setValue("Bearer \(cleanApiKey)", forHTTPHeaderField: "Authorization")
            }
            
            if let (data, response) = try? await session.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                struct ModelInfo: Codable {
                    let id: String
                }
                struct ModelList: Codable {
                    let data: [ModelInfo]
                }
                
                if let list = try? JSONDecoder().decode(ModelList.self, from: data) {
                    let ids = list.data.map { $0.id }
                    if !ids.isEmpty {
                        return ids.sorted()
                    }
                }
            }
        }
        
        // 2. Try Ollama direct /api/tags endpoint
        var ollamaBase = cleanURLString
        if ollamaBase.hasSuffix("v1/") {
            ollamaBase = ollamaBase.replacingOccurrences(of: "v1/", with: "")
        }
        
        if let ollamaURL = URL(string: ollamaBase + "api/tags") {
            var request = URLRequest(url: ollamaURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 4.0
            
            if let (data, response) = try? await session.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                struct OllamaModel: Codable {
                    let name: String
                }
                struct OllamaList: Codable {
                    let models: [OllamaModel]
                }
                
                if let list = try? JSONDecoder().decode(OllamaList.self, from: data) {
                    let names = list.models.map { $0.name }
                    if !names.isEmpty {
                        return names.sorted()
                    }
                }
            }
        }
        
        return []
    }
}

// MARK: - OpenAI JSON Request & Response Encodable Structs

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
            let role: String
            let content: String
        }
        let message: Message
    }
    
    let choices: [Choice]
}
