import Foundation

/// Spotify artist object
public struct SpotifyArtist: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let uri: String
    public let externalUrls: SpotifyExternalUrls
    public let href: String
    public let genres: [String]?
    public let images: [SpotifyImage]?
    public let popularity: Int?
    public let followers: [String: JSONValue]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String,
        name: String,
        type: String,
        uri: String,
        externalUrls: SpotifyExternalUrls,
        href: String,
        genres: [String]? = nil,
        images: [SpotifyImage]? = nil,
        popularity: Int? = nil,
        followers: [String: JSONValue]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.uri = uri
        self.externalUrls = externalUrls
        self.href = href
        self.genres = genres
        self.images = images
        self.popularity = popularity
        self.followers = followers
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.externalUrls = try container.decode(SpotifyExternalUrls.self, forKey: .externalUrls)
        self.href = try container.decode(String.self, forKey: .href)
        self.genres = try container.decodeIfPresent([String].self, forKey: .genres)
        self.images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images)
        self.popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
        self.followers = try container.decodeIfPresent([String: JSONValue].self, forKey: .followers)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.uri, forKey: .uri)
        try container.encode(self.externalUrls, forKey: .externalUrls)
        try container.encode(self.href, forKey: .href)
        try container.encodeIfPresent(self.genres, forKey: .genres)
        try container.encodeIfPresent(self.images, forKey: .images)
        try container.encodeIfPresent(self.popularity, forKey: .popularity)
        try container.encodeIfPresent(self.followers, forKey: .followers)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case type
        case uri
        case externalUrls = "external_urls"
        case href
        case genres
        case images
        case popularity
        case followers
    }
}