import Foundation

@MainActor
public final class Services {
    public static let shared = Services()
    
    public var locationService: LocationService?
    public var foursquareService: ContextualEnrichmentService?
    public var duckDuckGoService: ContextualEnrichmentService?
    public var contactService: ContactServiceProvider?
    public var weatherService: WeatherEnrichmentService?
    public var activityService: ActivityEnrichmentService?
    public var knowledgeGraphService: (any KnowledgeGraphRetrievalService & KnowledgeGraphIndexingService)?
    public var contextQuestionService: ContextQuestionService?
    public var pendingReprocessContext: ReprocessContext?
    
    private init() {}
}

public struct ReprocessContext {
    public let imageData: Data
    public let sessionID: String
    public let location: String?
    public let placeID: String?
    public let placeName: String?
    
    public init(imageData: Data, sessionID: String, location: String? = nil, placeID: String? = nil, placeName: String? = nil) {
        self.imageData = imageData
        self.sessionID = sessionID
        self.location = location
        self.placeID = placeID
        self.placeName = placeName
    }
}
