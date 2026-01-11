import XCTest
import CoreLocation
@testable import DiverKit

final class EnrichmentServiceTests: XCTestCase {
    
    func testFoursquareEnrichmentMock() async throws {
        // Since we don't have a real API key in tests, 
        // we verify that it returns nil when API key is missing.
        let service = FoursquareEnrichmentService(apiKey: nil)
        let location = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        
        let enrichment = try await service.enrich(location: location)
        XCTAssertNil(enrichment)
    }
    
    func testYahooEnrichmentMock() async throws {
        let service = YahooEnrichmentService(apiKey: "TEST_KEY")
        let query = "Blue Bottle Coffee"
        
        let enrichment = try await service.enrich(query: query, location: nil)
        
        XCTAssertNotNil(enrichment)
        XCTAssertTrue(enrichment?.title?.contains("Yahoo") == true)
        XCTAssertTrue(enrichment?.title?.contains(query) == true)
    }
    
    func testHierarchicalFlowMock() async throws {
        // Simulation of the hierarchical flow
        let fsService = FoursquareEnrichmentService(apiKey: nil) // Mocked behavior
        let yahooService = YahooEnrichmentService(apiKey: "TEST_KEY")
        
        let location = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        
        // Step 1: Foursquare (Mocked venue name)
        let venueName = "Mock Venue"
        
        // Step 2: Yahoo lookup using Foursquare result
        let finalEnrichment = try await yahooService.enrich(query: venueName, location: location)
        
        XCTAssertNotNil(finalEnrichment)
        XCTAssertEqual(finalEnrichment?.title, "Yahoo Result: Mock Venue")
    }
}
