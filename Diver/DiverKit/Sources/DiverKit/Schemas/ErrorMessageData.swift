import Foundation

/// Error message
public struct ErrorMessageData: Codable, Hashable, Sendable {
    /// Type of error (e.g., 'api_error', 'validation_error')
    public let errorType: String
    /// Error description
    public let errorMessage: String
    /// Stage where error occurred
    public let stage: String?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        errorType: String,
        errorMessage: String,
        stage: String? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.stage = stage
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.errorType = try container.decode(String.self, forKey: .errorType)
        self.errorMessage = try container.decode(String.self, forKey: .errorMessage)
        self.stage = try container.decodeIfPresent(String.self, forKey: .stage)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.errorType, forKey: .errorType)
        try container.encode(self.errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(self.stage, forKey: .stage)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case errorType = "error_type"
        case errorMessage = "error_message"
        case stage
    }
}