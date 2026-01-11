import Foundation

/// External URLs object
public struct SpotifyExternalUrls: Codable, Hashable, Sendable {
    public let spotify: String
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        spotify: String,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.spotify = spotify
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.spotify = try container.decode(String.self, forKey: .spotify)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.spotify, forKey: .spotify)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case spotify
    }
}