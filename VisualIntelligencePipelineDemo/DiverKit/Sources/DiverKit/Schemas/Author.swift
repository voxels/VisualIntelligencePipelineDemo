import Foundation

/// Schema for author data from OpenLibrary API
public struct Author: Codable, Hashable, Sendable {
    /// Author's full name
    public let name: String
    /// OpenLibrary author key (e.g., 'OL26320A')
    public let key: String?
    /// Personal name variant
    public let personalName: String?
    /// Biography (structured or plain text)
    public let bio: Bio?
    /// Birth date
    public let birthDate: String?
    /// Death date
    public let deathDate: String?
    /// External service IDs (VIAF, Wikidata, etc.)
    public let remoteIds: [String: String?]?
    /// Photo IDs or URLs
    public let photos: [AuthorPhotosItem]?
    /// Related links
    public let links: [AuthorLink]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        name: String,
        key: String? = nil,
        personalName: String? = nil,
        bio: Bio? = nil,
        birthDate: String? = nil,
        deathDate: String? = nil,
        remoteIds: [String: String?]? = nil,
        photos: [AuthorPhotosItem]? = nil,
        links: [AuthorLink]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.name = name
        self.key = key
        self.personalName = personalName
        self.bio = bio
        self.birthDate = birthDate
        self.deathDate = deathDate
        self.remoteIds = remoteIds
        self.photos = photos
        self.links = links
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.key = try container.decodeIfPresent(String.self, forKey: .key)
        self.personalName = try container.decodeIfPresent(String.self, forKey: .personalName)
        self.bio = try container.decodeIfPresent(Bio.self, forKey: .bio)
        self.birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        self.deathDate = try container.decodeIfPresent(String.self, forKey: .deathDate)
        self.remoteIds = try container.decodeIfPresent([String: String?].self, forKey: .remoteIds)
        self.photos = try container.decodeIfPresent([AuthorPhotosItem].self, forKey: .photos)
        self.links = try container.decodeIfPresent([AuthorLink].self, forKey: .links)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.name, forKey: .name)
        try container.encodeIfPresent(self.key, forKey: .key)
        try container.encodeIfPresent(self.personalName, forKey: .personalName)
        try container.encodeIfPresent(self.bio, forKey: .bio)
        try container.encodeIfPresent(self.birthDate, forKey: .birthDate)
        try container.encodeIfPresent(self.deathDate, forKey: .deathDate)
        try container.encodeIfPresent(self.remoteIds, forKey: .remoteIds)
        try container.encodeIfPresent(self.photos, forKey: .photos)
        try container.encodeIfPresent(self.links, forKey: .links)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case key
        case personalName = "personal_name"
        case bio
        case birthDate = "birth_date"
        case deathDate = "death_date"
        case remoteIds = "remote_ids"
        case photos
        case links
    }
}