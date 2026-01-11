import Foundation

/// Schema for returning reference data - includes ID and timestamps
public struct ReferenceRead: Codable, Hashable, Sendable {
    public let entityType: String
    public let name: String
    public let referenceMetadata: [String: JSONValue]?
    public let id: String
    public let userId: String?
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        entityType: String,
        name: String,
        referenceMetadata: [String: JSONValue]? = nil,
        id: String,
        userId: String? = nil,
        status: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.entityType = entityType
        self.name = name
        self.referenceMetadata = referenceMetadata
        self.id = id
        self.userId = userId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entityType = try container.decode(String.self, forKey: .entityType)
        self.name = try container.decode(String.self, forKey: .name)
        self.referenceMetadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .referenceMetadata)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId)
        self.status = try container.decode(String.self, forKey: .status)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.entityType, forKey: .entityType)
        try container.encode(self.name, forKey: .name)
        try container.encodeIfPresent(self.referenceMetadata, forKey: .referenceMetadata)
        try container.encode(self.id, forKey: .id)
        try container.encodeIfPresent(self.userId, forKey: .userId)
        try container.encode(self.status, forKey: .status)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encodeIfPresent(self.updatedAt, forKey: .updatedAt)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case entityType = "entity_type"
        case name
        case referenceMetadata = "reference_metadata"
        case id
        case userId = "user_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}