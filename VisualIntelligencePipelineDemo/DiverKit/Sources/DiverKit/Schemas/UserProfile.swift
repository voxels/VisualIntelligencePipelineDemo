import Foundation

/// Public user profile schema for external display.
public struct UserProfile: Codable, Hashable, Sendable {
    public let id: String
    public let username: String?
    public let firstName: String?
    public let lastName: String?
    public let avatarUrl: String?
    public let bio: String?
    public let profilePublic: Bool?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String,
        username: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        avatarUrl: String? = nil,
        bio: String? = nil,
        profilePublic: Bool? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.profilePublic = profilePublic
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        self.lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        self.avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
        self.profilePublic = try container.decodeIfPresent(Bool.self, forKey: .profilePublic)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.id, forKey: .id)
        try container.encodeIfPresent(self.username, forKey: .username)
        try container.encodeIfPresent(self.firstName, forKey: .firstName)
        try container.encodeIfPresent(self.lastName, forKey: .lastName)
        try container.encodeIfPresent(self.avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(self.bio, forKey: .bio)
        try container.encodeIfPresent(self.profilePublic, forKey: .profilePublic)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarUrl = "avatar_url"
        case bio
        case profilePublic = "profile_public"
    }
}