import Foundation

/// Item classification results from AI analysis
public struct ItemClassificationData: Codable, Hashable, Sendable {
    /// Item ID
    public let itemId: String
    /// Classification results (subset of ItemRead fields)
    public let classification: [String: JSONValue]
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        itemId: String,
        classification: [String: JSONValue],
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.itemId = itemId
        self.classification = classification
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.classification = try container.decode([String: JSONValue].self, forKey: .classification)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.itemId, forKey: .itemId)
        try container.encode(self.classification, forKey: .classification)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case itemId = "item_id"
        case classification
    }
}