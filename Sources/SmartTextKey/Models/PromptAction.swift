import Foundation

public struct PromptAction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var systemPrompt: String
    public var template: String
    public var shortcutId: String
    public var apiConfigId: UUID? // Stores the ID of the specific bound APIConfig, if any.
    
    public init(
        id: UUID = UUID(),
        title: String,
        systemPrompt: String,
        template: String,
        shortcutId: String,
        apiConfigId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.template = template
        self.shortcutId = shortcutId
        self.apiConfigId = apiConfigId
    }
}
