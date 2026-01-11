import Foundation

/// Extended ItemRead with relationship fields for endpoints that need them
public struct ItemReadWithRelations: Codable, Hashable, Sendable {
    public let title: String?
    public let description: String?
    public let hashtags: [String]?
    public let status: ItemStatusEnum?
    public let topic: [[String: JSONValue]]?
    public let summary: String?
    public let keyInsights: [String]?
    public let intent: String?
    public let entityType: String?
    public let modality: String?
    public let format: String?
    public let audienceLevel: String?
    public let timeliness: [String: JSONValue]?
    public let geography: [String]?
    public let language: String?
    public let tone: String?
    public let sourceType: String?
    public let evidence: [String: JSONValue]?
    public let safety: [String: JSONValue]?
    public let accessibility: [String: JSONValue]?
    public let videoAttrs: [String: JSONValue]?
    public let textAttrs: [String: JSONValue]?
    public let imageAttrs: [String: JSONValue]?
    public let engagement: [String: JSONValue]?
    public let dedupe: [String: JSONValue]?
    public let inputId: String?
    public let transcription: [String: JSONValue]?
    public let id: String
    public let createdAt: Date
    public let updatedAt: Date?
    public let referenceId: String?
    public let userId: String?
    public let noteId: String?
    public let logUrl: String?
    public let media: [JSONValue]?
    public let references: [String]?
    /// Additional properties that are not explicitly defined in the schema
    public let additionalProperties: [String: JSONValue]

    public init(
        title: String? = nil,
        description: String? = nil,
        hashtags: [String]? = nil,
        status: ItemStatusEnum? = nil,
        topic: [[String: JSONValue]]? = nil,
        summary: String? = nil,
        keyInsights: [String]? = nil,
        intent: String? = nil,
        entityType: String? = nil,
        modality: String? = nil,
        format: String? = nil,
        audienceLevel: String? = nil,
        timeliness: [String: JSONValue]? = nil,
        geography: [String]? = nil,
        language: String? = nil,
        tone: String? = nil,
        sourceType: String? = nil,
        evidence: [String: JSONValue]? = nil,
        safety: [String: JSONValue]? = nil,
        accessibility: [String: JSONValue]? = nil,
        videoAttrs: [String: JSONValue]? = nil,
        textAttrs: [String: JSONValue]? = nil,
        imageAttrs: [String: JSONValue]? = nil,
        engagement: [String: JSONValue]? = nil,
        dedupe: [String: JSONValue]? = nil,
        inputId: String? = nil,
        transcription: [String: JSONValue]? = nil,
        id: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        referenceId: String? = nil,
        userId: String? = nil,
        noteId: String? = nil,
        logUrl: String? = nil,
        media: [JSONValue]? = nil,
        references: [String]? = nil,
        additionalProperties: [String: JSONValue] = .init()
    ) {
        self.title = title
        self.description = description
        self.hashtags = hashtags
        self.status = status
        self.topic = topic
        self.summary = summary
        self.keyInsights = keyInsights
        self.intent = intent
        self.entityType = entityType
        self.modality = modality
        self.format = format
        self.audienceLevel = audienceLevel
        self.timeliness = timeliness
        self.geography = geography
        self.language = language
        self.tone = tone
        self.sourceType = sourceType
        self.evidence = evidence
        self.safety = safety
        self.accessibility = accessibility
        self.videoAttrs = videoAttrs
        self.textAttrs = textAttrs
        self.imageAttrs = imageAttrs
        self.engagement = engagement
        self.dedupe = dedupe
        self.inputId = inputId
        self.transcription = transcription
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.referenceId = referenceId
        self.userId = userId
        self.noteId = noteId
        self.logUrl = logUrl
        self.media = media
        self.references = references
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.hashtags = try container.decodeIfPresent([String].self, forKey: .hashtags)
        self.status = try container.decodeIfPresent(ItemStatusEnum.self, forKey: .status)
        self.topic = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .topic)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.keyInsights = try container.decodeIfPresent([String].self, forKey: .keyInsights)
        self.intent = try container.decodeIfPresent(String.self, forKey: .intent)
        self.entityType = try container.decodeIfPresent(String.self, forKey: .entityType)
        self.modality = try container.decodeIfPresent(String.self, forKey: .modality)
        self.format = try container.decodeIfPresent(String.self, forKey: .format)
        self.audienceLevel = try container.decodeIfPresent(String.self, forKey: .audienceLevel)
        self.timeliness = try container.decodeIfPresent([String: JSONValue].self, forKey: .timeliness)
        self.geography = try container.decodeIfPresent([String].self, forKey: .geography)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.tone = try container.decodeIfPresent(String.self, forKey: .tone)
        self.sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        self.evidence = try container.decodeIfPresent([String: JSONValue].self, forKey: .evidence)
        self.safety = try container.decodeIfPresent([String: JSONValue].self, forKey: .safety)
        self.accessibility = try container.decodeIfPresent([String: JSONValue].self, forKey: .accessibility)
        self.videoAttrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .videoAttrs)
        self.textAttrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .textAttrs)
        self.imageAttrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .imageAttrs)
        self.engagement = try container.decodeIfPresent([String: JSONValue].self, forKey: .engagement)
        self.dedupe = try container.decodeIfPresent([String: JSONValue].self, forKey: .dedupe)
        self.inputId = try container.decodeIfPresent(String.self, forKey: .inputId)
        self.transcription = try container.decodeIfPresent([String: JSONValue].self, forKey: .transcription)
        self.id = try container.decode(String.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.referenceId = try container.decodeIfPresent(String.self, forKey: .referenceId)
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId)
        self.noteId = try container.decodeIfPresent(String.self, forKey: .noteId)
        self.logUrl = try container.decodeIfPresent(String.self, forKey: .logUrl)
        self.media = try container.decodeIfPresent([JSONValue].self, forKey: .media)
        self.references = try container.decodeIfPresent([String].self, forKey: .references)
        self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encoder.encodeAdditionalProperties(self.additionalProperties)
        try container.encodeIfPresent(self.title, forKey: .title)
        try container.encodeIfPresent(self.description, forKey: .description)
        try container.encodeIfPresent(self.hashtags, forKey: .hashtags)
        try container.encodeIfPresent(self.status, forKey: .status)
        try container.encodeIfPresent(self.topic, forKey: .topic)
        try container.encodeIfPresent(self.summary, forKey: .summary)
        try container.encodeIfPresent(self.keyInsights, forKey: .keyInsights)
        try container.encodeIfPresent(self.intent, forKey: .intent)
        try container.encodeIfPresent(self.entityType, forKey: .entityType)
        try container.encodeIfPresent(self.modality, forKey: .modality)
        try container.encodeIfPresent(self.format, forKey: .format)
        try container.encodeIfPresent(self.audienceLevel, forKey: .audienceLevel)
        try container.encodeIfPresent(self.timeliness, forKey: .timeliness)
        try container.encodeIfPresent(self.geography, forKey: .geography)
        try container.encodeIfPresent(self.language, forKey: .language)
        try container.encodeIfPresent(self.tone, forKey: .tone)
        try container.encodeIfPresent(self.sourceType, forKey: .sourceType)
        try container.encodeIfPresent(self.evidence, forKey: .evidence)
        try container.encodeIfPresent(self.safety, forKey: .safety)
        try container.encodeIfPresent(self.accessibility, forKey: .accessibility)
        try container.encodeIfPresent(self.videoAttrs, forKey: .videoAttrs)
        try container.encodeIfPresent(self.textAttrs, forKey: .textAttrs)
        try container.encodeIfPresent(self.imageAttrs, forKey: .imageAttrs)
        try container.encodeIfPresent(self.engagement, forKey: .engagement)
        try container.encodeIfPresent(self.dedupe, forKey: .dedupe)
        try container.encodeIfPresent(self.inputId, forKey: .inputId)
        try container.encodeIfPresent(self.transcription, forKey: .transcription)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encodeIfPresent(self.updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(self.referenceId, forKey: .referenceId)
        try container.encodeIfPresent(self.userId, forKey: .userId)
        try container.encodeIfPresent(self.noteId, forKey: .noteId)
        try container.encodeIfPresent(self.logUrl, forKey: .logUrl)
        try container.encodeIfPresent(self.media, forKey: .media)
        try container.encodeIfPresent(self.references, forKey: .references)
    }

    /// Keys for encoding/decoding struct properties.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case description
        case hashtags
        case status
        case topic
        case summary
        case keyInsights = "key_insights"
        case intent
        case entityType = "entity_type"
        case modality
        case format
        case audienceLevel = "audience_level"
        case timeliness
        case geography
        case language
        case tone
        case sourceType = "source_type"
        case evidence
        case safety
        case accessibility
        case videoAttrs = "video_attrs"
        case textAttrs = "text_attrs"
        case imageAttrs = "image_attrs"
        case engagement
        case dedupe
        case inputId = "input_id"
        case transcription
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case referenceId = "reference_id"
        case userId = "user_id"
        case noteId = "note_id"
        case logUrl = "log_url"
        case media
        case references
    }
}