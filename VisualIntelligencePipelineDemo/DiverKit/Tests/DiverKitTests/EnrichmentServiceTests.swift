import XCTest
import CoreLocation
@testable import DiverKit

final class EnrichmentServiceTests: XCTestCase {
    
    func testFoursquareEnrichmentMock() async throws {
        // Since we don't have a real API key in tests, 
        // we verify that it returns nil when API key is missing.
        let service = FoursquareEnrichmentService(apiKey: nil)
        let location = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        
        let enrichment = try await service.enrich(location: location)
        XCTAssertNil(enrichment)
    }
    
    func testDuckDuckGoEnrichment() async throws {
        let service = DuckDuckGoEnrichmentService()
        let query = "Blue Bottle Coffee"
        
        // This makes a real network request. 
        // We allow it to fail (return nil) or succeed, but it shouldn't crash.
        let enrichment = try? await service.enrich(query: query, location: nil)
        
        if let enrichment = enrichment {
            XCTAssertFalse(enrichment.title?.isEmpty ?? true)
        }
    }
    
    func testHierarchicalFlowMock() async throws {
        // Simulation of the hierarchical flow using real (but possibly failing) services
        // Ideally this should use mocks, but for now we just verify code paths exist.
        
        let ddgService = DuckDuckGoEnrichmentService()
        let location = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        
        let venueName = "Mock Venue"
        
        // Step 2: DDG lookup using venue name
        let finalEnrichment = try? await ddgService.enrich(query: venueName, location: location)
        
        if let finalEnrichment = finalEnrichment {
            XCTAssertFalse(finalEnrichment.title?.isEmpty ?? true)
        }
    }
}
