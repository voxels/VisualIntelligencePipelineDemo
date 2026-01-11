import Foundation

/// Media analysis results - contains full MediaRead object
public struct MediaAnalysisData: Codable, Hashable, Sendable {
    /// Media entry ID
    public let mediaId: String
    /// Item ID
    public let itemId: String
    /// Full MediaRead object (includes thumbnails, transcription, extracted_text, themes, etc.)
    public let mediaData: MediaRead
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        mediaId: String,
        itemId: String,
        mediaData: MediaRead,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.mediaId = mediaId
        self.itemId = itemId
        self.mediaData = mediaData
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mediaId = try container.decode(String.self, forKey: .mediaId)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.mediaData = try container.decode(MediaRead.self, forKey: .mediaData)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.mediaId, forKey: .mediaId)
        try container.encode(self.itemId, forKey: .itemId)
        try container.encode(self.mediaData, forKey: .mediaData)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case mediaId = "media_id"
        case itemId = "item_id"
        case mediaData = "media_data"
    }
}