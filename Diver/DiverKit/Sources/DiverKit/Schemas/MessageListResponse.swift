import Foundation

/// Response schema for listing messages
public struct MessageListResponse: Codable, Hashable, Sendable {
    /// List of messages
    public let messages: [MessageRead]
    /// Whether there are more messages
    public let hasMore: Bool
    /// Cursor for next page
    public let nextCursor: Date?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        messages: [MessageRead],
        hasMore: Bool,
        nextCursor: Date? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.messages = messages
        self.hasMore = hasMore
        self.nextCursor = nextCursor
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = try container.decode([MessageRead].self, forKey: .messages)
        self.hasMore = try container.decode(Bool.self, forKey: .hasMore)
        self.nextCursor = try container.decodeIfPresent(Date.self, forKey: .nextCursor)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.messages, forKey: .messages)
        try container.encode(self.hasMore, forKey: .hasMore)
        try container.encodeIfPresent(self.nextCursor, forKey: .nextCursor)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case messages
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}