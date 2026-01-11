import Foundation

public struct HttpValidationError: Codable, Hashable, Sendable {
    public let detail: [ValidationError]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        detail: [ValidationError]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.detail = detail
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.detail = try container.decodeIfPresent([ValidationError].self, forKey: .detail)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.detail, forKey: .detail)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case detail
    }
}