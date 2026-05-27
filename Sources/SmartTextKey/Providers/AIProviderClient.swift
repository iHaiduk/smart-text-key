import Foundation

protocol AIProviderClient: Sendable {
    func complete(
        config: APIConfig,
        action: PromptAction,
        finalPrompt: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String

    func verifyConnection(baseURL: String, apiKey: String) async throws -> String
    func fetchAvailableModels(baseURL: String, apiKey: String) async -> [String]
}
