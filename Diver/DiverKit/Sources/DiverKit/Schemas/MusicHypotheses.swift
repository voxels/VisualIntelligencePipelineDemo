import Foundation

/// Music reference hypotheses from AI agent
public struct MusicHypotheses: Codable, Hashable, Sendable {
    /// Potential track/song names identified
    public let tracks: [String]?
    /// Potential album names identified
    public let albums: [String]?
    /// Potential artist/band names identified
    public let artists: [String]?
    /// Track-artist pairs with known relationships
    public let trackArtistPairs: [TrackArtistPair]?
    /// Album-artist pairs with known relationships
    public let albumArtistPairs: [AlbumArtistPair]?
    /// AI reasoning for the hypotheses generated
    public let rationales: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        tracks: [String]? = nil,
        albums: [String]? = nil,
        artists: [String]? = nil,
        trackArtistPairs: [TrackArtistPair]? = nil,
        albumArtistPairs: [AlbumArtistPair]? = nil,
        rationales: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
        self.trackArtistPairs = trackArtistPairs
        self.albumArtistPairs = albumArtistPairs
        self.rationales = rationales
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tracks = try container.decodeIfPresent([String].self, forKey: .tracks)
        self.albums = try container.decodeIfPresent([String].self, forKey: .albums)
        self.artists = try container.decodeIfPresent([String].self, forKey: .artists)
        self.trackArtistPairs = try container.decodeIfPresent([TrackArtistPair].self, forKey: .trackArtistPairs)
        self.albumArtistPairs = try container.decodeIfPresent([AlbumArtistPair].self, forKey: .albumArtistPairs)
        self.rationales = try container.decodeIfPresent(String.self, forKey: .rationales)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.tracks, forKey: .tracks)
        try container.encodeIfPresent(self.albums, forKey: .albums)
        try container.encodeIfPresent(self.artists, forKey: .artists)
        try container.encodeIfPresent(self.trackArtistPairs, forKey: .trackArtistPairs)
        try container.encodeIfPresent(self.albumArtistPairs, forKey: .albumArtistPairs)
        try container.encodeIfPresent(self.rationales, forKey: .rationales)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case tracks
        case albums
        case artists
        case trackArtistPairs = "track_artist_pairs"
        case albumArtistPairs = "album_artist_pairs"
        case rationales
    }
}