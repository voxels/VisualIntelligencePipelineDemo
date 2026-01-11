import Foundation

/// Typed message payload
public enum MessageCreateMessageData: Codable, Hashable, Sendable {
    case error(Error)
    case itemClassification(ItemClassification)
    case mediaAnalysis(MediaAnalysis)
    case processingStatus(ProcessingStatus)
    case referenceCandidates(ReferenceCandidates)
    case referenceHypotheses(ReferenceHypotheses)
    case referenceResults(ReferenceResults)
    case systemNotification(SystemNotification)
    case text(Text)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let discriminant = try container.decode(String.self, forKey: .messageType)
        switch discriminant {
        case "error":
            self = .error(try Error(from: decoder))
        case "item_classification":
            self = .itemClassification(try ItemClassification(from: decoder))
        case "media_analysis":
            self = .mediaAnalysis(try MediaAnalysis(from: decoder))
        case "processing_status":
            self = .processingStatus(try ProcessingStatus(from: decoder))
        case "reference_candidates":
            self = .referenceCandidates(try ReferenceCandidates(from: decoder))
        case "reference_hypotheses":
            self = .referenceHypotheses(try ReferenceHypotheses(from: decoder))
        case "reference_results":
            self = .referenceResults(try ReferenceResults(from: decoder))
        case "system_notification":
            self = .systemNotification(try SystemNotification(from: decoder))
        case "text":
            self = .text(try Text(from: decoder))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown shape discriminant value: \(discriminant)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws -> Void {
        switch self {
        case .error(let data):
            try data.encode(to: encoder)
        case .itemClassification(let data):
            try data.encode(to: encoder)
        case .mediaAnalysis(let data):
            try data.encode(to: encoder)
        case .processingStatus(let data):
            try data.encode(to: encoder)
        case .referenceCandidates(let data):
            try data.encode(to: encoder)
        case .referenceHypotheses(let data):
            try data.encode(to: encoder)
        case .referenceResults(let data):
            try data.encode(to: encoder)
        case .systemNotification(let data):
            try data.encode(to: encoder)
        case .text(let data):
            try data.encode(to: encoder)
        }
    }

    public struct Error: Codable, Hashable, Sendable {
        public let messageType: String = "error"
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
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.errorType, forKey: .errorType)
            try container.encode(self.errorMessage, forKey: .errorMessage)
            try container.encodeIfPresent(self.stage, forKey: .stage)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case errorType = "error_type"
            case errorMessage = "error_message"
            case stage
        }
    }

    public struct ItemClassification: Codable, Hashable, Sendable {
        public let messageType: String = "item_classification"
        /// Item ID
        public let itemId: String
        /// Classification results (subset of ItemRead fields)
        public let classification: [String: JSONValue]
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            itemId: String,
            classification: [String: JSONValue],
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.itemId = itemId
            self.classification = classification
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.itemId = try container.decode(String.self, forKey: .itemId)
            self.classification = try container.decode([String: JSONValue].self, forKey: .classification)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.itemId, forKey: .itemId)
            try container.encode(self.classification, forKey: .classification)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case itemId = "item_id"
            case classification
        }
    }

    public struct MediaAnalysis: Codable, Hashable, Sendable {
        public let messageType: String = "media_analysis"
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
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.mediaId, forKey: .mediaId)
            try container.encode(self.itemId, forKey: .itemId)
            try container.encode(self.mediaData, forKey: .mediaData)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case mediaId = "media_id"
            case itemId = "item_id"
            case mediaData = "media_data"
        }
    }

    public struct ProcessingStatus: Codable, Hashable, Sendable {
        public let messageType: String = "processing_status"
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
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.stage, forKey: .stage)
            try container.encode(self.message, forKey: .message)
            try container.encodeIfPresent(self.progress, forKey: .progress)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case stage
            case message
            case progress
        }
    }

    public struct ReferenceCandidates: Codable, Hashable, Sendable {
        public let messageType: String = "reference_candidates"
        /// Source of the search results
        public let searchSource: SearchSource
        /// Human-readable description of candidates found
        public let text: String
        /// Search results data
        public let searchResults: SearchResults
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            searchSource: SearchSource,
            text: String,
            searchResults: SearchResults,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.searchSource = searchSource
            self.text = text
            self.searchResults = searchResults
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.searchSource = try container.decode(SearchSource.self, forKey: .searchSource)
            self.text = try container.decode(String.self, forKey: .text)
            self.searchResults = try container.decode(SearchResults.self, forKey: .searchResults)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.searchSource, forKey: .searchSource)
            try container.encode(self.text, forKey: .text)
            try container.encode(self.searchResults, forKey: .searchResults)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case searchSource = "search_source"
            case text
            case searchResults = "search_results"
        }
    }

    public struct ReferenceHypotheses: Codable, Hashable, Sendable {
        public let messageType: String = "reference_hypotheses"
        /// Source that will be searched (e.g., 'spotify', 'openlibrary')
        public let searchSource: SearchSource
        /// Human-readable description of hypotheses
        public let text: String
        /// Hypothesis data (MusicHypotheses or BookHypotheses)
        public let hypotheses: Hypotheses
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            searchSource: SearchSource,
            text: String,
            hypotheses: Hypotheses,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.searchSource = searchSource
            self.text = text
            self.hypotheses = hypotheses
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.searchSource = try container.decode(SearchSource.self, forKey: .searchSource)
            self.text = try container.decode(String.self, forKey: .text)
            self.hypotheses = try container.decode(Hypotheses.self, forKey: .hypotheses)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.searchSource, forKey: .searchSource)
            try container.encode(self.text, forKey: .text)
            try container.encode(self.hypotheses, forKey: .hypotheses)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case searchSource = "search_source"
            case text
            case hypotheses
        }
    }

    public struct ReferenceResults: Codable, Hashable, Sendable {
        public let messageType: String = "reference_results"
        /// Source of the references
        public let searchSource: SearchSource
        /// Human-readable description of decision
        public let text: String
        /// Decision data with created references
        public let decisionResults: DecisionResults
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            searchSource: SearchSource,
            text: String,
            decisionResults: DecisionResults,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.searchSource = searchSource
            self.text = text
            self.decisionResults = decisionResults
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.searchSource = try container.decode(SearchSource.self, forKey: .searchSource)
            self.text = try container.decode(String.self, forKey: .text)
            self.decisionResults = try container.decode(DecisionResults.self, forKey: .decisionResults)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.searchSource, forKey: .searchSource)
            try container.encode(self.text, forKey: .text)
            try container.encode(self.decisionResults, forKey: .decisionResults)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case searchSource = "search_source"
            case text
            case decisionResults = "decision_results"
        }
    }

    public struct SystemNotification: Codable, Hashable, Sendable {
        public let messageType: String = "system_notification"
        /// Type of notification (e.g., 'user_joined', 'duplicate_content')
        public let notificationType: String
        /// Notification message
        public let message: String
        /// Additional notification data
        public let metadata: [String: JSONValue]?
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            notificationType: String,
            message: String,
            metadata: [String: JSONValue]? = nil,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.notificationType = notificationType
            self.message = message
            self.metadata = metadata
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.notificationType = try container.decode(String.self, forKey: .notificationType)
            self.message = try container.decode(String.self, forKey: .message)
            self.metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.notificationType, forKey: .notificationType)
            try container.encode(self.message, forKey: .message)
            try container.encodeIfPresent(self.metadata, forKey: .metadata)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case notificationType = "notification_type"
            case message
            case metadata
        }
    }

    public struct Text: Codable, Hashable, Sendable {
        public let messageType: String = "text"
        /// Message text content
        public let text: String
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            text: String,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.text = text
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.text = try container.decode(String.self, forKey: .text)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encode(self.messageType, forKey: .messageType)
            try container.encode(self.text, forKey: .text)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case messageType = "message_type"
            case text
        }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case messageType = "message_type"
    }
}