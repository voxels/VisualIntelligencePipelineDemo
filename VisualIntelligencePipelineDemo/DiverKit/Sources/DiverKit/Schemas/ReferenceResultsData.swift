import Foundation

/// Final AI decision with created references
public struct ReferenceResultsData: Codable, Hashable, Sendable {
    /// Source of the references
    public let searchSource: SearchSource
    /// Human-readable description of decision
    public let text: String
    /// Decision data with created references
    public let decisionResults: DecisionResults
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        searchSource: SearchSource,
        text: String,
        decisionResults: DecisionResults,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.searchSource = searchSource
        self.text = text
        self.decisionResults = decisionResults
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.searchSource = try container.decode(SearchSource.self, forKey: .searchSource)
        self.text = try container.decode(String.self, forKey: .text)
        self.decisionResults = try container.decode(DecisionResults.self, forKey: .decisionResults)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.searchSource, forKey: .searchSource)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.decisionResults, forKey: .decisionResults)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case searchSource = "search_source"
        case text
        case decisionResults = "decision_results"
    }
}