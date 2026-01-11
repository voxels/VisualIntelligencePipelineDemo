import Foundation

/// Search results from external APIs (Spotify, OpenLibrary, etc.)
public struct ReferenceCandidatesData: Codable, Hashable, Sendable {
    /// Source of the search results
    public let searchSource: SearchSource
    /// Human-readable description of candidates found
    public let text: String
    /// Search results data
    public let searchResults: SearchResults
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        searchSource: SearchSource,
        text: String,
        searchResults: SearchResults,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.searchSource = searchSource
        self.text = text
        self.searchResults = searchResults
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.searchSource = try container.decode(SearchSource.self, forKey: .searchSource)
        self.text = try container.decode(String.self, forKey: .text)
        self.searchResults = try container.decode(SearchResults.self, forKey: .searchResults)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.searchSource, forKey: .searchSource)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.searchResults, forKey: .searchResults)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case searchSource = "search_source"
        case text
        case searchResults = "search_results"
    }
}