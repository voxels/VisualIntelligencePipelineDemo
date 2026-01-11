import Foundation

/// Book reference hypotheses from AI agent
public struct BookHypotheses: Codable, Hashable, Sendable {
    /// Potential book titles identified
    public let titles: [String]?
    /// Potential author names identified
    public let authors: [String]?
    /// AI reasoning for the hypotheses generated
    public let rationales: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        titles: [String]? = nil,
        authors: [String]? = nil,
        rationales: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.titles = titles
        self.authors = authors
        self.rationales = rationales
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.titles = try container.decodeIfPresent([String].self, forKey: .titles)
        self.authors = try container.decodeIfPresent([String].self, forKey: .authors)
        self.rationales = try container.decodeIfPresent(String.self, forKey: .rationales)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.titles, forKey: .titles)
        try container.encodeIfPresent(self.authors, forKey: .authors)
        try container.encodeIfPresent(self.rationales, forKey: .rationales)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case titles
        case authors
        case rationales
    }
}