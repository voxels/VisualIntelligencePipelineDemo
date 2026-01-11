import Foundation

/// Track-artist pair with known relationship
public struct TrackArtistPair: Codable, Hashable, Sendable {
    /// Track/song name
    public let track: String
    /// Artist name for this track
    public let artist: String
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        track: String,
        artist: String,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.track = track
        self.artist = artist
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.track = try container.decode(String.self, forKey: .track)
        self.artist = try container.decode(String.self, forKey: .artist)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.track, forKey: .track)
        try container.encode(self.artist, forKey: .artist)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case track
        case artist
    }
}