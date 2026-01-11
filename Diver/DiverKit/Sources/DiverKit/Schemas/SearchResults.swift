import Foundation

/// Search results from any external API
public struct SearchResults: Codable, Hashable, Sendable {
    /// Search source type (music, book, etc.)
    public let type: Type
    /// List of search result candidates
    public let candidates: [SearchResultsOutputCandidatesItem]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        type: Type,
        candidates: [SearchResultsOutputCandidatesItem]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.type = type
        self.candidates = candidates
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(Type.self, forKey: .type)
        self.candidates = try container.decodeIfPresent([SearchResultsOutputCandidatesItem].self, forKey: .candidates)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.type, forKey: .type)
        try container.encodeIfPresent(self.candidates, forKey: .candidates)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case candidates
    }
}