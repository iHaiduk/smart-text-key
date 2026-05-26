import Foundation

public struct APIProvider: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let defaultBaseURL: String
    public let defaultModelName: String

    public static let openAICompatible = APIProvider(
        id: "openai-compatible",
        title: "OpenAI Compatible",
        defaultBaseURL: "https://api.openai.com/v1",
        defaultModelName: "gpt-4o"
    )

    public static let ollama = APIProvider(
        id: "ollama",
        title: "Ollama",
        defaultBaseURL: "http://localhost:11434",
        defaultModelName: "llama3"
    )

    public static let anthropic = APIProvider(
        id: "anthropic",
        title: "Anthropic",
        defaultBaseURL: "https://api.anthropic.com/v1",
        defaultModelName: "claude-3-5-sonnet-latest"
    )

    public static let deepSeek = APIProvider(
        id: "deepseek",
        title: "DeepSeek",
        defaultBaseURL: "https://api.deepseek.com/v1",
        defaultModelName: "deepseek-chat"
    )

    public static let all = [
        openAICompatible,
        ollama,
        anthropic,
        deepSeek
    ]

    public static func normalizedId(_ id: String?) -> String {
        guard let id, all.contains(where: { $0.id == id }) else {
            return openAICompatible.id
        }
        return id
    }

    public static func provider(for id: String) -> APIProvider {
        all.first(where: { $0.id == id }) ?? openAICompatible
    }
}
