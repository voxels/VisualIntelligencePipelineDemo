import Foundation

/// Processing pipeline status update
public struct ProcessingStatusData: Codable, Hashable, Sendable {
    /// Processing stage (e.g., 'analyzing', 'searching_references')
    public let stage: String
    /// Human-readable status message
    public let message: String
    /// Optional progress from 0.0 to 1.0
    public let progress: Double?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        stage: String,
        message: String,
        progress: Double? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.stage = stage
        self.message = message
        self.progress = progress
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stage = try container.decode(String.self, forKey: .stage)
        self.message = try container.decode(String.self, forKey: .message)
        self.progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.stage, forKey: .stage)
        try container.encode(self.message, forKey: .message)
        try container.encodeIfPresent(self.progress, forKey: .progress)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case stage
        case message
        case progress
    }
}