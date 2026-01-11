import Foundation

extension Requests {
    public struct AgentRegister: Codable, Hashable, Sendable {
        public let action: String?
        public let name: String
        public let purpose: String
        public let version: String
        public let hostname: String
        public let pid: Int
        public let capabilities: [String]
        public let pydanticSchema: [String: JSONValue]
        public let status: String?
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            action: String? = nil,
            name: String,
            purpose: String,
            version: String,
            hostname: String,
            pid: Int,
            capabilities: [String],
            pydanticSchema: [String: JSONValue],
            status: String? = nil,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.action = action
            self.name = name
            self.purpose = purpose
            self.version = version
            self.hostname = hostname
            self.pid = pid
            self.capabilities = capabilities
            self.pydanticSchema = pydanticSchema
            self.status = status
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.action = try container.decodeIfPresent(String.self, forKey: .action)
            self.name = try container.decode(String.self, forKey: .name)
            self.purpose = try container.decode(String.self, forKey: .purpose)
            self.version = try container.decode(String.self, forKey: .version)
            self.hostname = try container.decode(String.self, forKey: .hostname)
            self.pid = try container.decode(Int.self, forKey: .pid)
            self.capabilities = try container.decode([String].self, forKey: .capabilities)
            self.pydanticSchema = try container.decode([String: JSONValue].self, forKey: .pydanticSchema)
            self.status = try container.decodeIfPresent(String.self, forKey: .status)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encodeIfPresent(self.action, forKey: .action)
            try container.encode(self.name, forKey: .name)
            try container.encode(self.purpose, forKey: .purpose)
            try container.encode(self.version, forKey: .version)
            try container.encode(self.hostname, forKey: .hostname)
            try container.encode(self.pid, forKey: .pid)
            try container.encode(self.capabilities, forKey: .capabilities)
            try container.encode(self.pydanticSchema, forKey: .pydanticSchema)
            try container.encodeIfPresent(self.status, forKey: .status)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case action
            case name
            case purpose
            case version
            case hostname
            case pid
            case capabilities
            case pydanticSchema = "pydantic_schema"
            case status
        }
    }
}