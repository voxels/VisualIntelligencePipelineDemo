import Foundation
import SwiftData

// Services is NOT @MainActor — background tasks must be able to read service references
// without hopping to the main thread. Properties are set once at startup and then read-only.
public final class Services: @unchecked Sendable {
    public static let shared = Services()
    
    /// Shared ModelContext - single source of truth for all services
    /// Set this from the App's dataStore.mainContext at startup
    public var modelContext: ModelContext?
    
    public var locationService: LocationService?
    public var foursquareService: ContextualEnrichmentService?
    public var duckDuckGoService: ContextualEnrichmentService?
    public var contactService: ContactServiceProvider?
    public var weatherService: WeatherEnrichmentService?
    public var knowledgeGraphService: (any KnowledgeGraphRetrievalService & KnowledgeGraphIndexingService)?
    public var contextQuestionService: ContextQuestionService?
    public var dailyContextService: DailyContextService?
    public var pendingReprocessContext: ReprocessContext?
    public var mapKitService: MapKitEnrichmentService?
    public var metadataPipelineService: MetadataPipelineService?
    public var localPipelineService: LocalPipelineService?
    public var agenticSearchService: AgenticSearchService?
    public var edgeRouter: PipelineEdgeRouter?
    public var localDaemonService: EdgeDaemonService?
    public var actorSystem: VisualIntelligenceActorSystem?
    public var samService: (any SAM2Segmenting)?
    
    /// KnowMaps CloudCacheService for iCloud cache management
    public var cloudCacheService: Any?
    
    private init() {}
}

public struct ReprocessContext {
    public let imageData: Data
    public let sessionID: String
    public let sessionTitle: String?
    public let location: String?
    public let placeID: String?
    public let placeName: String?
    public let mediaType: String?
    
    public init(imageData: Data, sessionID: String, sessionTitle: String? = nil, location: String? = nil, placeID: String? = nil, placeName: String? = nil, mediaType: String? = nil) {
        self.imageData = imageData
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.location = location
        self.placeID = placeID
        self.placeName = placeName
        self.mediaType = mediaType
    }
}
