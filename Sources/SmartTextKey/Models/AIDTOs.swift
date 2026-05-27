import Foundation

struct ChatCompletionRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let choiceCount: Int?
    let stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case choiceCount = "n"
        case stream
    }
}

struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String
        }
        let message: Message
    }

    let choices: [Choice]
}

struct StreamResponse: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

struct ModelList: Codable {
    struct ModelInfo: Codable {
        let id: String
    }
    let data: [ModelInfo]
}

struct OllamaChatRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

struct OllamaChatResponse: Codable {
    struct Message: Codable {
        let content: String
    }

    let message: Message?
    let done: Bool?
}

struct OllamaModelList: Codable {
    struct Model: Codable {
        let name: String
    }

    let models: [Model]
}

struct AnthropicMessageRequest: Codable {
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

struct AnthropicMessageResponse: Codable {
    struct ContentBlock: Codable {
        let type: String?
        let text: String?
    }

    let content: [ContentBlock]
}

struct AnthropicStreamResponse: Codable {
    struct Delta: Codable {
        let type: String?
        let text: String?
    }

    let type: String
    let delta: Delta?
}
