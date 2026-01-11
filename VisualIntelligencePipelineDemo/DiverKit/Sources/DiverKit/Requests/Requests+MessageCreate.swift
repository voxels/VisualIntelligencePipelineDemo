import Foundation

extension Requests {
    public struct MessageCreate: Codable, Hashable, Sendable {
        /// Job/conversation UUID
        public let jobUuid: String
        /// Type of message (for backward compatibility)
        public let messageType: String
        /// Typed message payload
        public let messageData: MessageCreateMessageData
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            jobUuid: String,
            messageType: String,
            messageData: MessageCreateMessageData,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.jobUuid = jobUuid
            self.messageType = messageType
            self.messageData = messageData
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.jobUuid = try container.decode(String.self, forKey: .jobUuid)
            self.messageType = try container.decode(String.self, forKey: .messageType)
            self.messageData = try container.decode(MessageCreateMessageData.self, forKey: .messageData)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.jobUuid, forKey: .jobUuid)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.messageData, forKey: .messageData)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case jobUuid = "job_uuid"
            case messageType = "message_type"
            case messageData = "message_data"
        }
    }
}