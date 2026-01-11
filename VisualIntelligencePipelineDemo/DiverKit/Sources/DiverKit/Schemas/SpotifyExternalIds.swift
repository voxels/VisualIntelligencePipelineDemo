import Foundation

/// External IDs object
public struct SpotifyExternalIds: Codable, Hashable, Sendable {
    public let isrc: String?
    public let ean: String?
    public let upc: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        isrc: String? = nil,
        ean: String? = nil,
        upc: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.isrc = isrc
        self.ean = ean
        self.upc = upc
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isrc = try container.decodeIfPresent(String.self, forKey: .isrc)
        self.ean = try container.decodeIfPresent(String.self, forKey: .ean)
        self.upc = try container.decodeIfPresent(String.self, forKey: .upc)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.isrc, forKey: .isrc)
        try container.encodeIfPresent(self.ean, forKey: .ean)
        try container.encodeIfPresent(self.upc, forKey: .upc)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case isrc
        case ean
        case upc
    }
}