import Foundation
import SwiftData
import DiverShared

@Model
public final class ProcessedItem: Identifiable {
    public var id: String = UUID().uuidString
    public var inputId: String?
    public var url: String?
    public var title: String?
    public var summary: String?
    public var entityType: String?
    public var modality: String?
    public var tags: [String] = []
    public var createdAt: Date = Date()
    public var rawPayload: Data?

    // Phase 1 additions
    // Phase 1 additions
    public var statusRaw: String = ProcessingStatus.queued.rawValue
    
    @Transient
    public var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }
    public var isFavorite: Bool = false
    public var source: String?
    public var updatedAt: Date = Date()
    public var referenceCount: Int = 0
    public var lastProcessedAt: Date?
    public var wrappedLink: String?
    public var payloadRef: String?
    public var attributionID: String?
    public var masterCaptureID: String?
    public var sessionID: String?
    public var processingLog: [String] = [] // Debug/Audit Log
    public var failureCount: Int = 0
    
    // Media metadata
    public var transcription: String?
    public var themes: [String] = []
    public var mediaType: String?
    public var fileSize: Int?
    public var filename: String?
    
    // Enrichment metadata
    public var categories: [String] = []
    public var location: String?
    public var price: Double?
    public var rating: Double?
    public var purposes: Set<String> = [] // Migrated from single purpose
    public var productSearchURL: URL?
    

    
    // Detailed Context Storage (Data blobs)
    public var weatherContextData: Data?
    public var activityContextData: Data?
    public var placeContextData: Data?
    public var webContextData: Data?
    public var documentContextData: Data?
    public var qrContextData: Data?
    public var questions: [String] = [] 
    
    // Computed Accessors
    public var weatherContext: WeatherContext? {
        get { decode(weatherContextData) }
        set { weatherContextData = encode(newValue) }
    }
    
    public var activityContext: ActivityContext? {
        get { decode(activityContextData) }
        set { activityContextData = encode(newValue) }
    }
    
    public var placeContext: PlaceContext? {
        get { decode(placeContextData) }
        set { placeContextData = encode(newValue) }
    }
    
    public var webContext: WebContext? {
        get { decode(webContextData) }
        set { webContextData = encode(newValue) }
    }
    
    public var documentContext: DocumentContext? {
        get { decode(documentContextData) }
        set { documentContextData = encode(newValue) }
    }
    
    public var qrContext: QRCodeContext? {
        get { decode(qrContextData) }
        set { qrContextData = encode(newValue) }
    }
    
    private func decode<T: Codable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    private func encode<T: Codable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    @Relationship(deleteRule: .nullify, inverse: \ProcessedItem.childItems)
    public var parentItem: ProcessedItem?

    public var childItems: [ProcessedItem]?



    public init(
        id: String,
        inputId: String? = nil,
        url: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        entityType: String? = nil,
        modality: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        rawPayload: Data? = nil,
        status: ProcessingStatus = .queued,
        source: String? = nil,
        updatedAt: Date = Date(),
        referenceCount: Int = 0,
        lastProcessedAt: Date? = nil,
        wrappedLink: String? = nil,
        payloadRef: String? = nil,
        attributionID: String? = nil,
        masterCaptureID: String? = nil,
        sessionID: String? = nil,
        transcription: String? = nil,
        themes: [String] = [],
        mediaType: String? = nil,
        fileSize: Int? = nil,
        filename: String? = nil,
        categories: [String] = [],
        location: String? = nil,
        price: Double? = nil,
        rating: Double? = nil,
        purpose: String? = nil, // Deprecated argument
        purposes: Set<String> = [], // New argument
        processingLog: [String] = [],
        failureCount: Int = 0
    ) {
        self.id = id
        self.inputId = inputId
        self.url = url
        self.title = title
        self.summary = summary
        self.entityType = entityType
        self.modality = modality
        self.tags = tags
        self.createdAt = createdAt
        self.rawPayload = rawPayload
        self.rawPayload = rawPayload
        self.statusRaw = status.rawValue
        self.source = source
        self.source = source
        self.updatedAt = updatedAt
        self.referenceCount = referenceCount
        self.lastProcessedAt = lastProcessedAt
        self.wrappedLink = wrappedLink
        self.payloadRef = payloadRef
        self.attributionID = attributionID
        self.masterCaptureID = masterCaptureID
        self.sessionID = sessionID
        self.transcription = transcription
        self.themes = themes
        self.mediaType = mediaType
        self.fileSize = fileSize
        self.filename = filename
        self.categories = categories
        self.location = location
        self.price = price
        self.rating = rating
        
        // Migrate/Merge
        var combined = purposes
        if let p = purpose, !combined.contains(p) {
            combined.insert(p)
        }
        self.purposes = combined
        self.processingLog = processingLog
        self.failureCount = failureCount
    }

    
    public var mediaInfo: MediaMetadata {
        MediaMetadata(
            mediaType: mediaType,
            filename: filename,
            fileSize: fileSize,
            transcription: transcription,
            themes: themes
        )
    }
}

public struct MediaMetadata: Codable, Hashable, Sendable {
    public var mediaType: String?
    public var filename: String?
    public var fileSize: Int?
    public var transcription: String?
    public var themes: [String]
    
    public init(mediaType: String? = nil, filename: String? = nil, fileSize: Int? = nil, transcription: String? = nil, themes: [String] = []) {
        self.mediaType = mediaType
        self.filename = filename
        self.fileSize = fileSize
        self.transcription = transcription
        self.themes = themes
    }
}

// MARK: - Context Data Structs


