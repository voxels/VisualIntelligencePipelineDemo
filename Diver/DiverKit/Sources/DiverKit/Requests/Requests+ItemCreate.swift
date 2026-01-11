import Foundation

extension Requests {
    public struct ItemCreate: Codable, Hashable, Sendable {
        public let referenceId: String?
        public let userId: String?
        public let title: String?
        public let description: String?
        public let hashtags: [String]?
        public let status: String?
        public let topic: [[String: JSONValue]]?
        public let intent: String?
        public let entityType: String?
        public let modality: String?
        public let format: String?
        public let audienceLevel: String?
        public let language: String?
        public let tone: String?
        public let sourceType: String?
        public let geography: [String: JSONValue]?
        public let evidence: [String: JSONValue]?
        public let safety: [String: JSONValue]?
        public let accessibility: [String: JSONValue]?
        public let timeliness: [String: JSONValue]?
        public let videoAttrs: [String: JSONValue]?
        public let textAttrs: [String: JSONValue]?
        public let imageAttrs: [String: JSONValue]?
        public let authority: [String: JSONValue]?
        public let engagement: [String: JSONValue]?
        public let dedupe: [String: JSONValue]?
        public let inputId: String?
        public let transcription: String?
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            referenceId: String? = nil,
            userId: String? = nil,
            title: String? = nil,
            description: String? = nil,
            hashtags: [String]? = nil,
            status: String? = nil,
            topic: [[String: JSONValue]]? = nil,
            intent: String? = nil,
            entityType: String? = nil,
            modality: String? = nil,
            format: String? = nil,
            audienceLevel: String? = nil,
            language: String? = nil,
            tone: String? = nil,
            sourceType: String? = nil,
            geography: [String: JSONValue]? = nil,
            evidence: [String: JSONValue]? = nil,
            safety: [String: JSONValue]? = nil,
            accessibility: [String: JSONValue]? = nil,
            timeliness: [String: JSONValue]? = nil,
            videoAttrs: [String: JSONValue]? = nil,
            textAttrs: [String: JSONValue]? = nil,
            imageAttrs: [String: JSONValue]? = nil,
            authority: [String: JSONValue]? = nil,
            engagement: [String: JSONValue]? = nil,
            dedupe: [String: JSONValue]? = nil,
            inputId: String? = nil,
            transcription: String? = nil,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.referenceId = referenceId
            self.userId = userId
            self.title = title
            self.description = description
            self.hashtags = hashtags
            self.status = status
            self.topic = topic
            self.intent = intent
            self.entityType = entityType
            self.modality = modality
            self.format = format
            self.audienceLevel = audienceLevel
            self.language = language
            self.tone = tone
            self.sourceType = sourceType
            self.geography = geography
            self.evidence = evidence
            self.safety = safety
            self.accessibility = accessibility
            self.timeliness = timeliness
            self.videoAttrs = videoAttrs
            self.textAttrs = textAttrs
            self.imageAttrs = imageAttrs
            self.authority = authority
            self.engagement = engagement
            self.dedupe = dedupe
            self.inputId = inputId
            self.transcription = transcription
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.referenceId = try container.decodeIfPresent(String.self, forKey: .referenceId)
            self.userId = try container.decodeIfPresent(String.self, forKey: .userId)
            self.title = try container.decodeIfPresent(String.self, forKey: .title)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)
            self.hashtags = try container.decodeIfPresent([String].self, forKey: .hashtags)
            self.status = try container.decodeIfPresent(String.self, forKey: .status)
            self.topic = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .topic)
            self.intent = try container.decodeIfPresent(String.self, forKey: .intent)
            self.entityType = try container.decodeIfPresent(String.self, forKey: .entityType)
            self.modality = try container.decodeIfPresent(String.self, forKey: .modality)
            self.format = try container.decodeIfPresent(String.self, forKey: .format)
            self.audienceLevel = try container.decodeIfPresent(String.self, forKey: .audienceLevel)
            self.language = try container.decodeIfPresent(String.self, forKey: .language)
            self.tone = try container.decodeIfPresent(String.self, forKey: .tone)
            self.sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
            self.geography = try container.decodeIfPresent([String: JSONValue].self, forKey: .geography)
            self.evidence = try container.decodeIfPresent([String: JSONValue].self, forKey: .evidence)
            self.safety = try container.decodeIfPresent([String: JSONValue].self, forKey: .safety)
            self.accessibility = try container.decodeIfPresent([String: JSONValue].self, forKey: .accessibility)
            self.timeliness = try container.decodeIfPresent([String: JSONValue].self, forKey: .timeliness)
            self.videoAttrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .videoAttrs)
            self.textAttrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .textAttrs)
            self.imageAttrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .imageAttrs)
            self.authority = try container.decodeIfPresent([String: JSONValue].self, forKey: .authority)
            self.engagement = try container.decodeIfPresent([String: JSONValue].self, forKey: .engagement)
            self.dedupe = try container.decodeIfPresent([String: JSONValue].self, forKey: .dedupe)
            self.inputId = try container.decodeIfPresent(String.self, forKey: .inputId)
            self.transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encodeIfPresent(self.referenceId, forKey: .referenceId)
            try container.encodeIfPresent(self.userId, forKey: .userId)
            try container.encodeIfPresent(self.title, forKey: .title)
            try container.encodeIfPresent(self.description, forKey: .description)
            try container.encodeIfPresent(self.hashtags, forKey: .hashtags)
            try container.encodeIfPresent(self.status, forKey: .status)
            try container.encodeIfPresent(self.topic, forKey: .topic)
            try container.encodeIfPresent(self.intent, forKey: .intent)
            try container.encodeIfPresent(self.entityType, forKey: .entityType)
            try container.encodeIfPresent(self.modality, forKey: .modality)
            try container.encodeIfPresent(self.format, forKey: .format)
            try container.encodeIfPresent(self.audienceLevel, forKey: .audienceLevel)
            try container.encodeIfPresent(self.language, forKey: .language)
            try container.encodeIfPresent(self.tone, forKey: .tone)
            try container.encodeIfPresent(self.sourceType, forKey: .sourceType)
            try container.encodeIfPresent(self.geography, forKey: .geography)
            try container.encodeIfPresent(self.evidence, forKey: .evidence)
            try container.encodeIfPresent(self.safety, forKey: .safety)
            try container.encodeIfPresent(self.accessibility, forKey: .accessibility)
            try container.encodeIfPresent(self.timeliness, forKey: .timeliness)
            try container.encodeIfPresent(self.videoAttrs, forKey: .videoAttrs)
            try container.encodeIfPresent(self.textAttrs, forKey: .textAttrs)
            try container.encodeIfPresent(self.imageAttrs, forKey: .imageAttrs)
            try container.encodeIfPresent(self.authority, forKey: .authority)
            try container.encodeIfPresent(self.engagement, forKey: .engagement)
            try container.encodeIfPresent(self.dedupe, forKey: .dedupe)
            try container.encodeIfPresent(self.inputId, forKey: .inputId)
            try container.encodeIfPresent(self.transcription, forKey: .transcription)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case referenceId = "reference_id"
            case userId = "user_id"
            case title
            case description
            case hashtags
            case status
            case topic
            case intent
            case entityType = "entity_type"
            case modality
            case format
            case audienceLevel = "audience_level"
            case language
            case tone
            case sourceType = "source_type"
            case geography
            case evidence
            case safety
            case accessibility
            case timeliness
            case videoAttrs = "video_attrs"
            case textAttrs = "text_attrs"
            case imageAttrs = "image_attrs"
            case authority
            case engagement
            case dedupe
            case inputId = "input_id"
            case transcription
        }
    }
}