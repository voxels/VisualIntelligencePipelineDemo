import Foundation

/// System notification message
public struct SystemNotificationData: Codable, Hashable, Sendable {
    /// Type of notification (e.g., 'user_joined', 'duplicate_content')
    public let notificationType: String
    /// Notification message
    public let message: String
    /// Additional notification data
    public let metadata: [String: JSONValue]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        notificationType: String,
        message: String,
        metadata: [String: JSONValue]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.notificationType = notificationType
        self.message = message
        self.metadata = metadata
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.notificationType = try container.decode(String.self, forKey: .notificationType)
        self.message = try container.decode(String.self, forKey: .message)
        self.metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.notificationType, forKey: .notificationType)
        try container.encode(self.message, forKey: .message)
        try container.encodeIfPresent(self.metadata, forKey: .metadata)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case notificationType = "notification_type"
        case message
        case metadata
    }
}