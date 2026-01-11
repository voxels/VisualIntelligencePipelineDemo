import Foundation

/// Album-artist pair with known relationship
public struct AlbumArtistPair: Codable, Hashable, Sendable {
    /// Album name
    public let album: String
    /// Artist name for this album
    public let artist: String
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        album: String,
        artist: String,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.album = album
        self.artist = artist
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.album = try container.decode(String.self, forKey: .album)
        self.artist = try container.decode(String.self, forKey: .artist)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.album, forKey: .album)
        try container.encode(self.artist, forKey: .artist)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case album
        case artist
    }
}