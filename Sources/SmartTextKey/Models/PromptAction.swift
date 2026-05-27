import Foundation

public struct PromptAction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var systemPrompt: String
    public var template: String
    public var shortcutId: String
    public var apiConfigId: UUID? // Stores the ID of the specific bound APIConfig, if any.
    public var responseSuffix: String? // Custom text to append to the end of the AI-generated response.
    public var bundleId: String? // Optional application bundle ID binding
    public var isSnippet: Bool // Set to true for static text expansions
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case systemPrompt
        case template
        case shortcutId
        case apiConfigId
        case responseSuffix
        case bundleId
        case isSnippet
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        systemPrompt: String,
        template: String,
        shortcutId: String,
        apiConfigId: UUID? = nil,
        responseSuffix: String? = nil,
        bundleId: String? = nil,
        isSnippet: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.template = template
        self.shortcutId = shortcutId
        self.apiConfigId = apiConfigId
        self.responseSuffix = responseSuffix
        self.bundleId = bundleId
        self.isSnippet = isSnippet
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        self.template = try container.decode(String.self, forKey: .template)
        self.shortcutId = try container.decode(String.self, forKey: .shortcutId)
        self.apiConfigId = try container.decodeIfPresent(UUID.self, forKey: .apiConfigId)
        self.responseSuffix = try container.decodeIfPresent(String.self, forKey: .responseSuffix)
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        self.isSnippet = try container.decodeIfPresent(Bool.self, forKey: .isSnippet) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(template, forKey: .template)
        try container.encode(shortcutId, forKey: .shortcutId)
        try container.encodeIfPresent(apiConfigId, forKey: .apiConfigId)
        try container.encodeIfPresent(responseSuffix, forKey: .responseSuffix)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encode(isSnippet, forKey: .isSnippet)
    }
}
