import Foundation

/// AI-generated hypotheses about references to search for
public struct ReferenceHypothesesData: Codable, Hashable, Sendable {
    /// Source that will be searched (e.g., 'spotify', 'openlibrary')
    public let searchSource: SearchSource
    /// Human-readable description of hypotheses
    public let text: String
    /// Hypothesis data (MusicHypotheses or BookHypotheses)
    public let hypotheses: Hypotheses
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        searchSource: SearchSource,
        text: String,
        hypotheses: Hypotheses,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.searchSource = searchSource
        self.text = text
        self.hypotheses = hypotheses
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.searchSource = try container.decode(SearchSource.self, forKey: .searchSource)
        self.text = try container.decode(String.self, forKey: .text)
        self.hypotheses = try container.decode(Hypotheses.self, forKey: .hypotheses)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.searchSource, forKey: .searchSource)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.hypotheses, forKey: .hypotheses)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case searchSource = "search_source"
        case text
        case hypotheses
    }
}