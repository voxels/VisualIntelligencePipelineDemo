import Foundation

/// Reference decision results from any source
public struct DecisionResults: Codable, Hashable, Sendable {
    /// Decision source type (music, book, etc.)
    public let type: Type
    /// Created references
    public let createdReferences: [ReferenceRead]?
    /// AI reasoning for selections
    public let reasoning: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        type: Type,
        createdReferences: [ReferenceRead]? = nil,
        reasoning: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.type = type
        self.createdReferences = createdReferences
        self.reasoning = reasoning
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(Type.self, forKey: .type)
        self.createdReferences = try container.decodeIfPresent([ReferenceRead].self, forKey: .createdReferences)
        self.reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.type, forKey: .type)
        try container.encodeIfPresent(self.createdReferences, forKey: .createdReferences)
        try container.encodeIfPresent(self.reasoning, forKey: .reasoning)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case createdReferences = "created_references"
        case reasoning
    }
}