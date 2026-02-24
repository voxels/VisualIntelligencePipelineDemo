import Foundation
import SwiftData
import knowmaps
import DiverShared
import DiverKit

@MainActor
final class KnowMapsServiceContainer {
    let cacheModelContainer: ModelContainer
    let cacheModelContext: ModelContext
    let analyticsService: AnalyticsService
    let cacheService: CloudCacheService
    let cacheManager: CloudCacheManager
    let cacheStore: KnowMapsCacheStore
    let modelController: DefaultModelController
    let authenticationService: knowmaps.AppleAuthenticationService
    let initializationError: Error?
    let queueStore: DiverQueueStore?
    let queueProcessingService: DiverQueueProcessingService?
    let foursquareEnrichmentService: FoursquareLinkEnrichmentService
    let locationProvider: DiverKit.LocationService

    init(
        container: ModelContainer,
        analyticsService: AnalyticsService = SegmentAnalyticsService.shared,
        queueDirectoryURL: URL? = nil
    ) {
        self.cacheModelContainer = container
        self.cacheModelContext = ModelContext(container)
        self.analyticsService = analyticsService
        self.cacheService = CloudCacheService(analyticsManager: analyticsService, modelContext: cacheModelContext)
        self.cacheManager = CloudCacheManager(cloudCacheService: cacheService, analyticsManager: analyticsService)
        self.cacheStore = KnowMapsCacheStore(cacheService: cacheService)
        self.authenticationService = knowmaps.AppleAuthenticationService.shared
        self.initializationError = nil // Setup error now handled upstream
        
        // Initialize DefaultModelController dependencies
        let messagesDelegate = NoOpMessagesDelegate()
        let assistiveHost = AssistiveChatHostService(analyticsManager: analyticsService, messagesDelegate: messagesDelegate)
        let personalizedSearchSession = PersonalizedSearchSession(cloudCacheService: cacheService)
        let placeSearchSession = PlaceSearchSession()
        
        let placeSearch = DefaultPlaceSearchService(
            assistiveHostDelegate: assistiveHost,
            placeSearchSession: placeSearchSession,
            personalizedSearchSession: personalizedSearchSession,
            analyticsManager: analyticsService
        )
        
        // Use KnowMaps LocationProvider if available or mock it? 
        // DefaultLocationService needs a LocationProvider. DefaultLocationService is in knowmaps.
        // LocationProvider.shared might be available if it's public.
        // Let's assume LocationProvider exists in knowmaps and is accessible (based on Know_MapsApp.swift).
        let locationService = DefaultLocationService(locationProvider: knowmaps.LocationProvider.shared)
        
        let recommenderService = DefaultRecommenderService()
        let inputValidator = DefaultInputValidationServiceV2()
        let resultIndexer = DefaultResultIndexServiceV2()

        self.modelController = DefaultModelController(
            assistiveHost: assistiveHost,
            locationService: locationService,
            placeSearchService: placeSearch,
            analyticsManager: analyticsService,
            recommenderService: recommenderService,
            cacheManager: cacheManager,
            inputValidator: inputValidator,
            resultIndexer: resultIndexer
        )

        var resolvedQueueStore: DiverQueueStore?

        let resolvedQueueURL = AppGroupContainer.queueDirectoryURL()
        if let queueURL = resolvedQueueURL {
            if let store = try? DiverQueueStore(directoryURL: queueURL) {
                resolvedQueueStore = store

            }
        }

        self.queueStore = resolvedQueueStore
        self.foursquareEnrichmentService = FoursquareLinkEnrichmentService(modelController: modelController)
        self.locationProvider = DiverKit.LocationService()
        
        // Initialize Services
        let webViewService = DiverKit.WebViewLinkEnrichmentService()
        let duckDuckGoService = DiverKit.DuckDuckGoEnrichmentService()
        
        // Use composite service: Foursquare (specific) -> WebView (generic)
        let compositeLinkService = DiverKit.CompositeLinkEnrichmentService(services: [
            self.foursquareEnrichmentService,
            webViewService
        ])
        
        if let store = resolvedQueueStore {
             self.queueProcessingService = DiverQueueProcessingService(
                queueStore: store,
                cacheStore: cacheStore,
                linkEnrichmentService: compositeLinkService,
                contextEnrichmentService: duckDuckGoService
            )
        } else {
            self.queueProcessingService = nil
        }
    }

    func processPendingQueue() async throws {
        try await queueProcessingService?.processPendingQueue()
    }
}

fileprivate final class NoOpMessagesDelegate: AssistiveChatHostMessagesDelegate, @unchecked Sendable {
    func addReceivedMessage(caption: String, parameters: AssistiveChatHostQueryParameters, isLocalParticipant: Bool, filters: Dictionary<String, String>, modelController: ModelController, overrideIntent: AssistiveChatHostService.Intent?, selectedDestinationLocation: LocationResult?) async throws {}
    func updateQueryParametersHistory(with parameters: AssistiveChatHostQueryParameters, modelController: ModelController) async {}
}
