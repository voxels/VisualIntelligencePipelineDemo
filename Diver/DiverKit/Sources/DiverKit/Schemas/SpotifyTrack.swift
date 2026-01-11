import Foundation

/// Spotify track object
public struct SpotifyTrack: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let album: SpotifyAlbum
    public let artists: [SpotifyArtist]
    public let availableMarkets: [String]?
    public let discNumber: Int
    public let durationMs: Int
    public let explicit: Bool
    public let externalIds: SpotifyExternalIds?
    public let externalUrls: SpotifyExternalUrls
    public let href: String
    public let isPlayable: Bool?
    public let previewUrl: String?
    public let trackNumber: Int
    public let type: String
    public let uri: String
    public let popularity: Int?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String,
        name: String,
        album: SpotifyAlbum,
        artists: [SpotifyArtist],
        availableMarkets: [String]? = nil,
        discNumber: Int,
        durationMs: Int,
        explicit: Bool,
        externalIds: SpotifyExternalIds? = nil,
        externalUrls: SpotifyExternalUrls,
        href: String,
        isPlayable: Bool? = nil,
        previewUrl: String? = nil,
        trackNumber: Int,
        type: String,
        uri: String,
        popularity: Int? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.id = id
        self.name = name
        self.album = album
        self.artists = artists
        self.availableMarkets = availableMarkets
        self.discNumber = discNumber
        self.durationMs = durationMs
        self.explicit = explicit
        self.externalIds = externalIds
        self.externalUrls = externalUrls
        self.href = href
        self.isPlayable = isPlayable
        self.previewUrl = previewUrl
        self.trackNumber = trackNumber
        self.type = type
        self.uri = uri
        self.popularity = popularity
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.album = try container.decode(SpotifyAlbum.self, forKey: .album)
        self.artists = try container.decode([SpotifyArtist].self, forKey: .artists)
        self.availableMarkets = try container.decodeIfPresent([String].self, forKey: .availableMarkets)
        self.discNumber = try container.decode(Int.self, forKey: .discNumber)
        self.durationMs = try container.decode(Int.self, forKey: .durationMs)
        self.explicit = try container.decode(Bool.self, forKey: .explicit)
        self.externalIds = try container.decodeIfPresent(SpotifyExternalIds.self, forKey: .externalIds)
        self.externalUrls = try container.decode(SpotifyExternalUrls.self, forKey: .externalUrls)
        self.href = try container.decode(String.self, forKey: .href)
        self.isPlayable = try container.decodeIfPresent(Bool.self, forKey: .isPlayable)
        self.previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
        self.trackNumber = try container.decode(Int.self, forKey: .trackNumber)
        self.type = try container.decode(String.self, forKey: .type)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.album, forKey: .album)
        try container.encode(self.artists, forKey: .artists)
        try container.encodeIfPresent(self.availableMarkets, forKey: .availableMarkets)
        try container.encode(self.discNumber, forKey: .discNumber)
        try container.encode(self.durationMs, forKey: .durationMs)
        try container.encode(self.explicit, forKey: .explicit)
        try container.encodeIfPresent(self.externalIds, forKey: .externalIds)
        try container.encode(self.externalUrls, forKey: .externalUrls)
        try container.encode(self.href, forKey: .href)
        try container.encodeIfPresent(self.isPlayable, forKey: .isPlayable)
        try container.encodeIfPresent(self.previewUrl, forKey: .previewUrl)
        try container.encode(self.trackNumber, forKey: .trackNumber)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.uri, forKey: .uri)
        try container.encodeIfPresent(self.popularity, forKey: .popularity)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case album
        case artists
        case availableMarkets = "available_markets"
        case discNumber = "disc_number"
        case durationMs = "duration_ms"
        case explicit
        case externalIds = "external_ids"
        case externalUrls = "external_urls"
        case href
        case isPlayable = "is_playable"
        case previewUrl = "preview_url"
        case trackNumber = "track_number"
        case type
        case uri
        case popularity
    }
}