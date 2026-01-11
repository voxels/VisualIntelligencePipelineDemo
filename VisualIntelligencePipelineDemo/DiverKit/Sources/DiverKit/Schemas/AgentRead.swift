import Foundation

/// Schema for returning agent data
public struct AgentRead: Codable, Hashable, Sendable {
    public let agentId: String
    public let name: String
    public let purpose: String
    public let version: String
    public let hostname: String
    public let pid: Int
    public let capabilities: [String]
    public let pydanticSchema: [String: JSONValue]
    public let status: String
    public let uptime: Double
    public let memoryUsage: [String: JSONValue]?
    public let queueStats: [String: JSONValue]?
    public let lastHeartbeat: Date
    public let createdAt: Date
    public let updatedAt: Date
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        agentId: String,
        name: String,
        purpose: String,
        version: String,
        hostname: String,
        pid: Int,
        capabilities: [String],
        pydanticSchema: [String: JSONValue],
        status: String,
        uptime: Double,
        memoryUsage: [String: JSONValue]? = nil,
        queueStats: [String: JSONValue]? = nil,
        lastHeartbeat: Date,
        createdAt: Date,
        updatedAt: Date,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.agentId = agentId
        self.name = name
        self.purpose = purpose
        self.version = version
        self.hostname = hostname
        self.pid = pid
        self.capabilities = capabilities
        self.pydanticSchema = pydanticSchema
        self.status = status
        self.uptime = uptime
        self.memoryUsage = memoryUsage
        self.queueStats = queueStats
        self.lastHeartbeat = lastHeartbeat
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agentId = try container.decode(String.self, forKey: .agentId)
        self.name = try container.decode(String.self, forKey: .name)
        self.purpose = try container.decode(String.self, forKey: .purpose)
        self.version = try container.decode(String.self, forKey: .version)
        self.hostname = try container.decode(String.self, forKey: .hostname)
        self.pid = try container.decode(Int.self, forKey: .pid)
        self.capabilities = try container.decode([String].self, forKey: .capabilities)
        self.pydanticSchema = try container.decode([String: JSONValue].self, forKey: .pydanticSchema)
        self.status = try container.decode(String.self, forKey: .status)
        self.uptime = try container.decode(Double.self, forKey: .uptime)
        self.memoryUsage = try container.decodeIfPresent([String: JSONValue].self, forKey: .memoryUsage)
        self.queueStats = try container.decodeIfPresent([String: JSONValue].self, forKey: .queueStats)
        self.lastHeartbeat = try container.decode(Date.self, forKey: .lastHeartbeat)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encode(self.agentId, forKey: .agentId)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.purpose, forKey: .purpose)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.hostname, forKey: .hostname)
        try container.encode(self.pid, forKey: .pid)
        try container.encode(self.capabilities, forKey: .capabilities)
        try container.encode(self.pydanticSchema, forKey: .pydanticSchema)
        try container.encode(self.status, forKey: .status)
        try container.encode(self.uptime, forKey: .uptime)
        try container.encodeIfPresent(self.memoryUsage, forKey: .memoryUsage)
        try container.encodeIfPresent(self.queueStats, forKey: .queueStats)
        try container.encode(self.lastHeartbeat, forKey: .lastHeartbeat)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encode(self.updatedAt, forKey: .updatedAt)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case agentId = "agent_id"
        case name
        case purpose
        case version
        case hostname
        case pid
        case capabilities
        case pydanticSchema = "pydantic_schema"
        case status
        case uptime
        case memoryUsage = "memory_usage"
        case queueStats = "queue_stats"
        case lastHeartbeat = "last_heartbeat"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}