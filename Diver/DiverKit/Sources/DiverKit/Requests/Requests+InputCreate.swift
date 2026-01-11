import Foundation

extension Requests {
    public struct InputCreate: Codable, Hashable, Sendable {
        public let inputType: InputTypeEnum
        public let source: String
        public let inputMetadata: [String: JSONValue]?
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            inputType: InputTypeEnum,
            source: String,
            inputMetadata: [String: JSONValue]? = nil,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.inputType = inputType
            self.source = source
            self.inputMetadata = inputMetadata
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.inputType = try container.decode(InputTypeEnum.self, forKey: .inputType)
            self.source = try container.decode(String.self, forKey: .source)
            self.inputMetadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .inputMetadata)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.inputType, forKey: .inputType)
            try container.encode(self.source, forKey: .source)
            try container.encodeIfPresent(self.inputMetadata, forKey: .inputMetadata)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case inputType = "input_type"
            case source
            case inputMetadata = "input_metadata"
        }
    }
}