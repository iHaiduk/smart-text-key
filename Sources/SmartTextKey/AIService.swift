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

struct AIProviderClientFactory: Sendable {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func makeClient(for providerId: String) -> any AIProviderClient {
        switch APIProvider.normalizedId(providerId) {
        case APIProvider.ollama.id:
            return OllamaProviderClient(session: session)
        case APIProvider.anthropic.id:
            return AnthropicProviderClient(session: session)
        case APIProvider.deepSeek.id:
            return OpenAICompatibleProviderClient(defaultBaseURL: APIProvider.deepSeek.defaultBaseURL, session: session)
        default:
            return OpenAICompatibleProviderClient(defaultBaseURL: APIProvider.openAICompatible.defaultBaseURL, session: session)
        }
    }
}

public final class AIService: AIClientProtocol, Sendable {
    public static let shared = AIService()

    private let factory: AIProviderClientFactory
    private let settings: AppSettings

    public init(session: URLSession = .shared, settings: AppSettings = .shared) {
        self.factory = AIProviderClientFactory(session: session)
        self.settings = settings
    }

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
        
        let apiSettings = settings
        let activeLanguage = apiSettings.resolvedLanguageName()
        finalPrompt = finalPrompt.replacingOccurrences(of: "{{LANGUAGE}}", with: activeLanguage)
        let config: APIConfig
        if let boundId = action.apiConfigId,
           let boundConfig = apiSettings.apiConfigs.first(where: { $0.id == boundId }) {
            config = boundConfig
        } else {
            config = apiSettings.activeConfig
        }

        var resultText: String
        do {
            resultText = try await executeRequest(config: config, action: action, finalPrompt: finalPrompt, onChunk: onChunk)
        } catch {
            if let fallbackId = config.fallbackConfigId,
               let fallbackConfig = apiSettings.apiConfigs.first(where: { $0.id == fallbackId }) {
                AppLogger.aiService.warning("Primary API failed. Retrying with fallback: [\(fallbackConfig.name)]")
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

    private func providerClient(for providerId: String) -> any AIProviderClient {
        factory.makeClient(for: providerId)
    }
}
