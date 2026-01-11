import Foundation

/// Schema for book data from OpenLibrary API
public struct OpenLibraryBook: Codable, Hashable, Sendable {
    /// Book title
    public let title: String
    /// OpenLibrary work ID (e.g., 'OL123456W')
    public let openlibraryId: String?
    /// List of authors
    public let authors: [Author]?
    /// Publication date or year
    public let publishedDate: String?
    /// ISBN identifier
    public let isbn: String?
    /// Publisher name
    public let publisher: String?
    /// Book description
    public let description: String?
    /// Cover image URL
    public let coverUrl: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        title: String,
        openlibraryId: String? = nil,
        authors: [Author]? = nil,
        publishedDate: String? = nil,
        isbn: String? = nil,
        publisher: String? = nil,
        description: String? = nil,
        coverUrl: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.title = title
        self.openlibraryId = openlibraryId
        self.authors = authors
        self.publishedDate = publishedDate
        self.isbn = isbn
        self.publisher = publisher
        self.description = description
        self.coverUrl = coverUrl
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.openlibraryId = try container.decodeIfPresent(String.self, forKey: .openlibraryId)
        self.authors = try container.decodeIfPresent([Author].self, forKey: .authors)
        self.publishedDate = try container.decodeIfPresent(String.self, forKey: .publishedDate)
        self.isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        self.publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.title, forKey: .title)
        try container.encodeIfPresent(self.openlibraryId, forKey: .openlibraryId)
        try container.encodeIfPresent(self.authors, forKey: .authors)
        try container.encodeIfPresent(self.publishedDate, forKey: .publishedDate)
        try container.encodeIfPresent(self.isbn, forKey: .isbn)
        try container.encodeIfPresent(self.publisher, forKey: .publisher)
        try container.encodeIfPresent(self.description, forKey: .description)
        try container.encodeIfPresent(self.coverUrl, forKey: .coverUrl)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case openlibraryId = "openlibrary_id"
        case authors
        case publishedDate = "published_date"
        case isbn
        case publisher
        case description
        case coverUrl = "cover_url"
    }
}