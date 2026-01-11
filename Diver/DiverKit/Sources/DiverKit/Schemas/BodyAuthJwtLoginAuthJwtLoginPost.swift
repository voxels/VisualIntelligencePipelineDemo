import Foundation

public struct BodyAuthJwtLoginAuthJwtLoginPost: Codable, Hashable, Sendable {
    public let grantType: String?
    public let username: String
    public let password: String
    public let scope: String?
    public let clientId: String?
    public let clientSecret: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        grantType: String? = nil,
        username: String,
        password: String,
        scope: String? = nil,
        clientId: String? = nil,
        clientSecret: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.grantType = grantType
        self.username = username
        self.password = password
        self.scope = scope
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.grantType = try container.decodeIfPresent(String.self, forKey: .grantType)
        self.username = try container.decode(String.self, forKey: .username)
        self.password = try container.decode(String.self, forKey: .password)
        self.scope = try container.decodeIfPresent(String.self, forKey: .scope)
        self.clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        self.clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.grantType, forKey: .grantType)
        try container.encode(self.username, forKey: .username)
        try container.encode(self.password, forKey: .password)
        try container.encodeIfPresent(self.scope, forKey: .scope)
        try container.encodeIfPresent(self.clientId, forKey: .clientId)
        try container.encodeIfPresent(self.clientSecret, forKey: .clientSecret)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case grantType = "grant_type"
        case username
        case password
        case scope
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }
}