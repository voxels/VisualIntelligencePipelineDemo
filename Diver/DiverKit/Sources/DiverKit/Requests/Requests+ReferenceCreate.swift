import Foundation

extension Requests {
    public struct ReferenceCreate: Codable, Hashable, Sendable {
        public let entityType: String
        public let name: String
        public let referenceMetadata: [String: JSONValue]?
        /// List of creators with name and role
        public let creators: [[String: String]]?
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            entityType: String,
            name: String,
            referenceMetadata: [String: JSONValue]? = nil,
            creators: [[String: String]]? = nil,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.entityType = entityType
            self.name = name
            self.referenceMetadata = referenceMetadata
            self.creators = creators
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.entityType = try container.decode(String.self, forKey: .entityType)
            self.name = try container.decode(String.self, forKey: .name)
            self.referenceMetadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .referenceMetadata)
            self.creators = try container.decodeIfPresent([[String: String]].self, forKey: .creators)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.entityType, forKey: .entityType)
            try container.encode(self.name, forKey: .name)
            try container.encodeIfPresent(self.referenceMetadata, forKey: .referenceMetadata)
            try container.encodeIfPresent(self.creators, forKey: .creators)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case entityType = "entity_type"
            case name
            case referenceMetadata = "reference_metadata"
            case creators
        }
    }
}