import Foundation

/// Schema for updating user data.
public struct UserUpdate: Codable, Hashable, Sendable {
    public let password: String?
    public let email: String?
    public let isActive: Bool?
    public let isSuperuser: Bool?
    public let isVerified: Bool?
    public let username: String?
    public let phone: String?
    public let firstName: String?
    public let lastName: String?
    public let bio: String?
    public let timezone: String?
    public let language: String?
    public let profilePublic: Bool?
    public let allowNotifications: Bool?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        password: String? = nil,
        email: String? = nil,
        isActive: Bool? = nil,
        isSuperuser: Bool? = nil,
        isVerified: Bool? = nil,
        username: String? = nil,
        phone: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        bio: String? = nil,
        timezone: String? = nil,
        language: String? = nil,
        profilePublic: Bool? = nil,
        allowNotifications: Bool? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.password = password
        self.email = email
        self.isActive = isActive
        self.isSuperuser = isSuperuser
        self.isVerified = isVerified
        self.username = username
        self.phone = phone
        self.firstName = firstName
        self.lastName = lastName
        self.bio = bio
        self.timezone = timezone
        self.language = language
        self.profilePublic = profilePublic
        self.allowNotifications = allowNotifications
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.password = try container.decodeIfPresent(String.self, forKey: .password)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        self.isSuperuser = try container.decodeIfPresent(Bool.self, forKey: .isSuperuser)
        self.isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified)
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.phone = try container.decodeIfPresent(String.self, forKey: .phone)
        self.firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        self.lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
        self.timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.profilePublic = try container.decodeIfPresent(Bool.self, forKey: .profilePublic)
        self.allowNotifications = try container.decodeIfPresent(Bool.self, forKey: .allowNotifications)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.password, forKey: .password)
        try container.encodeIfPresent(self.email, forKey: .email)
        try container.encodeIfPresent(self.isActive, forKey: .isActive)
        try container.encodeIfPresent(self.isSuperuser, forKey: .isSuperuser)
        try container.encodeIfPresent(self.isVerified, forKey: .isVerified)
        try container.encodeIfPresent(self.username, forKey: .username)
        try container.encodeIfPresent(self.phone, forKey: .phone)
        try container.encodeIfPresent(self.firstName, forKey: .firstName)
        try container.encodeIfPresent(self.lastName, forKey: .lastName)
        try container.encodeIfPresent(self.bio, forKey: .bio)
        try container.encodeIfPresent(self.timezone, forKey: .timezone)
        try container.encodeIfPresent(self.language, forKey: .language)
        try container.encodeIfPresent(self.profilePublic, forKey: .profilePublic)
        try container.encodeIfPresent(self.allowNotifications, forKey: .allowNotifications)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case password
        case email
        case isActive = "is_active"
        case isSuperuser = "is_superuser"
        case isVerified = "is_verified"
        case username
        case phone
        case firstName = "first_name"
        case lastName = "last_name"
        case bio
        case timezone
        case language
        case profilePublic = "profile_public"
        case allowNotifications = "allow_notifications"
    }
}