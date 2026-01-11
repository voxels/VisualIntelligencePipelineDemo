import Foundation

/// Schema for reading a message
public struct MessageRead: Codable, Hashable, Sendable {
    /// Job/conversation UUID
    public let jobUuid: String
    /// Type of message
    public let messageType: String
    /// Typed message payload
    public let messageData: MessageReadMessageData
    /// Message ID
    public let id: String
    /// Sender type: 'user', 'agent', or 'system'
    public let senderType: String
    /// Sender identifier
    public let senderId: String?
    /// Message creation timestamp
    public let createdAt: Date
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        jobUuid: String,
        messageType: String,
        messageData: MessageReadMessageData,
        id: String,
        senderType: String,
        senderId: String? = nil,
        createdAt: Date,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.jobUuid = jobUuid
        self.messageType = messageType
        self.messageData = messageData
        self.id = id
        self.senderType = senderType
        self.senderId = senderId
        self.createdAt = createdAt
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jobUuid = try container.decode(String.self, forKey: .jobUuid)
        self.messageType = try container.decode(String.self, forKey: .messageType)
        self.messageData = try container.decode(MessageReadMessageData.self, forKey: .messageData)
        self.id = try container.decode(String.self, forKey: .id)
        self.senderType = try container.decode(String.self, forKey: .senderType)
        self.senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.jobUuid, forKey: .jobUuid)
        try container.encode(self.messageType, forKey: .messageType)
        try container.encode(self.messageData, forKey: .messageData)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.senderType, forKey: .senderType)
        try container.encodeIfPresent(self.senderId, forKey: .senderId)
        try container.encode(self.createdAt, forKey: .createdAt)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case jobUuid = "job_uuid"
        case messageType = "message_type"
        case messageData = "message_data"
        case id
        case senderType = "sender_type"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }
}