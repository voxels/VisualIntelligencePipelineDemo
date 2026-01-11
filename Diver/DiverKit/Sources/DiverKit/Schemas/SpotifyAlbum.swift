import Foundation

/// Spotify album object
public struct SpotifyAlbum: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let albumType: String
    public let totalTracks: Int
    public let availableMarkets: [String]?
    public let externalUrls: SpotifyExternalUrls
    public let href: String
    public let images: [SpotifyImage]?
    public let releaseDate: String
    public let releaseDatePrecision: String
    public let type: String
    public let uri: String
    public let artists: [SpotifyArtist]
    public let externalIds: SpotifyExternalIds?
    public let genres: [String]?
    public let label: String?
    public let popularity: Int?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String,
        name: String,
        albumType: String,
        totalTracks: Int,
        availableMarkets: [String]? = nil,
        externalUrls: SpotifyExternalUrls,
        href: String,
        images: [SpotifyImage]? = nil,
        releaseDate: String,
        releaseDatePrecision: String,
        type: String,
        uri: String,
        artists: [SpotifyArtist],
        externalIds: SpotifyExternalIds? = nil,
        genres: [String]? = nil,
        label: String? = nil,
        popularity: Int? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.id = id
        self.name = name
        self.albumType = albumType
        self.totalTracks = totalTracks
        self.availableMarkets = availableMarkets
        self.externalUrls = externalUrls
        self.href = href
        self.images = images
        self.releaseDate = releaseDate
        self.releaseDatePrecision = releaseDatePrecision
        self.type = type
        self.uri = uri
        self.artists = artists
        self.externalIds = externalIds
        self.genres = genres
        self.label = label
        self.popularity = popularity
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.albumType = try container.decode(String.self, forKey: .albumType)
        self.totalTracks = try container.decode(Int.self, forKey: .totalTracks)
        self.availableMarkets = try container.decodeIfPresent([String].self, forKey: .availableMarkets)
        self.externalUrls = try container.decode(SpotifyExternalUrls.self, forKey: .externalUrls)
        self.href = try container.decode(String.self, forKey: .href)
        self.images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images)
        self.releaseDate = try container.decode(String.self, forKey: .releaseDate)
        self.releaseDatePrecision = try container.decode(String.self, forKey: .releaseDatePrecision)
        self.type = try container.decode(String.self, forKey: .type)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.artists = try container.decode([SpotifyArtist].self, forKey: .artists)
        self.externalIds = try container.decodeIfPresent(SpotifyExternalIds.self, forKey: .externalIds)
        self.genres = try container.decodeIfPresent([String].self, forKey: .genres)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.albumType, forKey: .albumType)
        try container.encode(self.totalTracks, forKey: .totalTracks)
        try container.encodeIfPresent(self.availableMarkets, forKey: .availableMarkets)
        try container.encode(self.externalUrls, forKey: .externalUrls)
        try container.encode(self.href, forKey: .href)
        try container.encodeIfPresent(self.images, forKey: .images)
        try container.encode(self.releaseDate, forKey: .releaseDate)
        try container.encode(self.releaseDatePrecision, forKey: .releaseDatePrecision)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.uri, forKey: .uri)
        try container.encode(self.artists, forKey: .artists)
        try container.encodeIfPresent(self.externalIds, forKey: .externalIds)
        try container.encodeIfPresent(self.genres, forKey: .genres)
        try container.encodeIfPresent(self.label, forKey: .label)
        try container.encodeIfPresent(self.popularity, forKey: .popularity)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case albumType = "album_type"
        case totalTracks = "total_tracks"
        case availableMarkets = "available_markets"
        case externalUrls = "external_urls"
        case href
        case images
        case releaseDate = "release_date"
        case releaseDatePrecision = "release_date_precision"
        case type
        case uri
        case artists
        case externalIds = "external_ids"
        case genres
        case label
        case popularity
    }
}