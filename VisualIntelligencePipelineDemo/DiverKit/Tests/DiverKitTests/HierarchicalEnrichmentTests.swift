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
        let unifiedDataManager = try! UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        modelContext = unifiedDataManager.mainContext
        pipeline = LocalPipelineService(modelContext: modelContext)
    }
    
    @MainActor
    func testEndToEndHierarchicalFlow() async throws {
        // 1. Setup Mocks
        let mockLocation = CLLocation(latitude: 34.0522, longitude: -118.2437) // LA
        let locationProvider = MockLocationProvider(location: mockLocation)
        
        // 2. Setup Input
        let input = LocalInput(url: "https://example.com/checkin", inputType: "web")
        modelContext.insert(input)
        
        let descriptor = DiverItemDescriptor(
            id: "hierarchical-test",
            url: "https://example.com/checkin",
            title: "Coffee Shop Checkin",
            type: .web
        )
        
        // 3. Process using current API
        let processed = try await pipeline.process(
            input: input,
            descriptor: descriptor,
            locationService: locationProvider
        )
        
        // 4. Verify basic processing completed
        XCTAssertEqual(processed.id, "hierarchical-test")
        XCTAssertEqual(processed.title, "Coffee Shop Checkin")
        XCTAssertEqual(processed.status, .ready)
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

    func fetchDetails(for id: String) async throws -> EnrichmentData? {
        return data
    }
}
