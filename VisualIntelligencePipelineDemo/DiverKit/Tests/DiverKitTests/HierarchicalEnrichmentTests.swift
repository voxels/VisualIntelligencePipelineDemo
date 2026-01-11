import XCTest
import CoreLocation
import SwiftData
import DiverShared
@testable import DiverKit

final class HierarchicalEnrichmentTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var pipeline: LocalPipelineService!
    
    @MainActor
    override func setUp() async throws {
        let unifiedDataManager = UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        modelContext = unifiedDataManager.mainContext
        pipeline = LocalPipelineService(modelContext: modelContext)
    }
    
    @MainActor
    func testEndToEndHierarchicalFlow() async throws {
        // 1. Setup Mocks
        let mockLocation = CLLocation(latitude: 34.0522, longitude: -118.2437) // LA
        let locationProvider = MockLocationProvider(location: mockLocation)
        
        let fsEnrichment = EnrichmentData(
            title: "Foursquare Coffee Shop",
            categories: ["Coffee", "Cafe"],
            location: "LA Arts District",
            price: 2,
            rating: 8.5
        )
        let foursquareService = HierarchicalMockEnrichmentService(data: fsEnrichment)
        
        let ddgEnrichment = EnrichmentData(
            title: "DuckDuckGo Result: Foursquare Coffee Shop",
            descriptionText: "Best coffee in LA according to DDG",
            styleTags: ["Popular", "Local Favorite"]
        )
        let ddgService = HierarchicalMockEnrichmentService(data: ddgEnrichment)
        
        // 2. Setup Input
        let input = LocalInput(url: "https://example.com/checkin", inputType: "web")
        modelContext.insert(input)
        
        // 3. Process
        let processed = try await pipeline.process(
            input: input,
            locationService: locationProvider,
            foursquareService: foursquareService,
            duckDuckGoService: ddgService
        )
        
        // 4. Verify Chaining
        // Foursquare should have been called first
        XCTAssertTrue(foursquareService.enrichLocationCalled)
        
        // DDG should have been called with the Foursquare title
        XCTAssertTrue(ddgService.allQueries.contains("Foursquare Coffee Shop"))
        XCTAssertTrue(ddgService.enrichQueryCalled)
        
        // Final item should have merged data
        XCTAssertEqual(processed.title, "DuckDuckGo Result: Foursquare Coffee Shop")
        XCTAssertEqual(processed.summary, "Best coffee in LA according to DDG")
        XCTAssertTrue(processed.tags.contains("Coffee"))
        XCTAssertTrue(processed.tags.contains("Popular"))
        XCTAssertEqual(processed.location, "LA Arts District")
        XCTAssertEqual(processed.price, 2)
        XCTAssertEqual(processed.rating, 8.5)
    }
}

// MARK: - Mocks

final class MockLocationProvider: LocationProvider {
    let location: CLLocation?
    init(location: CLLocation?) { self.location = location }
    func getCurrentLocation() async -> CLLocation? { return location }
}

final class HierarchicalMockEnrichmentService: ContextualEnrichmentService, @unchecked Sendable {
    let data: EnrichmentData?
    var enrichLocationCalled = false
    var enrichQueryCalled = false
    var lastQuery: String?
    var allQueries: [String] = []
    
    init(data: EnrichmentData?) { self.data = data }
    
    func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        enrichLocationCalled = true
        return data
    }
    
    func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        enrichQueryCalled = true
        lastQuery = query
        allQueries.append(query)
        return data
    }

    func searchNearby(location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        return data != nil ? [data!] : []
    }

    func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        return data != nil ? [data!] : []
    }
}
