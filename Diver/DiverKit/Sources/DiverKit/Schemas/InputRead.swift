import Foundation

/// Schema for returning Input data.
public struct InputRead: Codable, Hashable, Sendable {
    public let inputType: InputTypeEnum
    public let source: String
    public let inputMetadata: [String: JSONValue]?
    public let id: String
    public let createdAt: Date
    public let items: [ItemRead]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        inputType: InputTypeEnum,
        source: String,
        inputMetadata: [String: JSONValue]? = nil,
        id: String,
        createdAt: Date,
        items: [ItemRead]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.inputType = inputType
        self.source = source
        self.inputMetadata = inputMetadata
        self.id = id
        self.createdAt = createdAt
        self.items = items
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inputType = try container.decode(InputTypeEnum.self, forKey: .inputType)
        self.source = try container.decode(String.self, forKey: .source)
        self.inputMetadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .inputMetadata)
        self.id = try container.decode(String.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.items = try container.decodeIfPresent([ItemRead].self, forKey: .items)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.inputType, forKey: .inputType)
        try container.encode(self.source, forKey: .source)
        try container.encodeIfPresent(self.inputMetadata, forKey: .inputMetadata)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encodeIfPresent(self.items, forKey: .items)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case inputType = "input_type"
        case source
        case inputMetadata = "input_metadata"
        case id
        case createdAt = "created_at"
        case items
    }
}