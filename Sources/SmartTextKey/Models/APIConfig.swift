import Foundation

public struct APIConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var apiBaseURL: String
    public var apiKey: String
    public var modelName: String
    public var providerId: String
    public var fallbackConfigId: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case apiBaseURL
        case apiKey
        case modelName
        case providerId
        case fallbackConfigId
    }

    public init(
        id: UUID = UUID(),
        name: String,
        apiBaseURL: String,
        apiKey: String,
        modelName: String,
        providerId: String = APIProvider.openAICompatible.id,
        fallbackConfigId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.providerId = APIProvider.normalizedId(providerId)
        self.fallbackConfigId = fallbackConfigId
    }

    // Custom decoding to fetch apiKey securely from Apple Keychain (with automatic migration)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        modelName = try container.decode(String.self, forKey: .modelName)
        providerId = APIProvider.normalizedId(try container.decodeIfPresent(String.self, forKey: .providerId))
        fallbackConfigId = try container.decodeIfPresent(UUID.self, forKey: .fallbackConfigId)

        let decodedApiKey = try container.decode(String.self, forKey: .apiKey)
        let keychainKey = "com.smarttextkey.apikey.\(id.uuidString)"

        if !decodedApiKey.isEmpty {
            // Auto-migrate from plaintext UserDefaults to secure Keychain
            KeychainHelper.shared.save(key: keychainKey, value: decodedApiKey)
            apiKey = decodedApiKey
        } else {
            // Read from secure Keychain
            apiKey = KeychainHelper.shared.read(key: keychainKey) ?? ""
        }
    }

    // Custom encoding to write apiKey securely to Apple Keychain and store empty string in plist files
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(apiBaseURL, forKey: .apiBaseURL)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(APIProvider.normalizedId(providerId), forKey: .providerId)
        try container.encodeIfPresent(fallbackConfigId, forKey: .fallbackConfigId)

        let keychainKey = "com.smarttextkey.apikey.\(id.uuidString)"
        KeychainHelper.shared.save(key: keychainKey, value: apiKey)

        // Wipe API key from plist for user privacy
        try container.encode("", forKey: .apiKey)
    }
}
