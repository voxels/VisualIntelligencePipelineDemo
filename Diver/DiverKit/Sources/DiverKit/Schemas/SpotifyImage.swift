import Foundation

/// Spotify image object
public struct SpotifyImage: Codable, Hashable, Sendable {
    public let url: String
    public let height: Int?
    public let width: Int?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        url: String,
        height: Int? = nil,
        width: Int? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.url = url
        self.height = height
        self.width = width
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.height = try container.decodeIfPresent(Int.self, forKey: .height)
        self.width = try container.decodeIfPresent(Int.self, forKey: .width)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.url, forKey: .url)
        try container.encodeIfPresent(self.height, forKey: .height)
        try container.encodeIfPresent(self.width, forKey: .width)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case url
        case height
        case width
    }
}