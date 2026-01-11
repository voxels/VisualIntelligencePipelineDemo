import Foundation

public struct ValidationError: Codable, Hashable, Sendable {
    public let loc: [ValidationErrorLocItem]
    public let msg: String
    public let type: String
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        loc: [ValidationErrorLocItem],
        msg: String,
        type: String,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.loc = loc
        self.msg = msg
        self.type = type
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.loc = try container.decode([ValidationErrorLocItem].self, forKey: .loc)
        self.msg = try container.decode(String.self, forKey: .msg)
        self.type = try container.decode(String.self, forKey: .type)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.loc, forKey: .loc)
        try container.encode(self.msg, forKey: .msg)
        try container.encode(self.type, forKey: .type)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case loc
        case msg
        case type
    }
}