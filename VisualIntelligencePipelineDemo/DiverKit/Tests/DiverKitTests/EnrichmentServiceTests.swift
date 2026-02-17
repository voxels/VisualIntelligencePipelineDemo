import XCTest
import CoreLocation
import SwiftData
@testable import DiverKit

/// Tests for enrichment services using mocks — no real network calls.
final class EnrichmentServiceTests: XCTestCase {
    
    // MARK: - Contextual Enrichment Mock Tests
    
    func testMockContextualEnrichment_LocationReturnsData() async throws {
        let mockData = EnrichmentData(
            title: "Central Park",
            descriptionText: "Famous urban park",
            categories: ["Park", "Recreation"],
            location: "New York, NY",
            rating: 4.8
        )
        let mock = MockContextualEnrichmentService(locationResult: mockData)
        let location = CLLocationCoordinate2D(latitude: 40.7829, longitude: -73.9654)
        
        let result = try await mock.enrich(location: location)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Central Park")
        XCTAssertEqual(result?.categories, ["Park", "Recreation"])
        XCTAssertEqual(result?.rating, 4.8)
        XCTAssertEqual(mock.enrichLocationCallCount, 1)
    }
    
    func testMockContextualEnrichment_QueryReturnsData() async throws {
        let mockData = EnrichmentData(
            title: "Blue Bottle Coffee",
            descriptionText: "Specialty coffee",
            categories: ["Coffee"],
            location: "San Francisco"
        )
        let mock = MockContextualEnrichmentService(queryResult: mockData)
        
        let result = try await mock.enrich(query: "Blue Bottle", location: nil)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Blue Bottle Coffee")
        XCTAssertEqual(mock.enrichQueryCallCount, 1)
    }
    
    func testMockContextualEnrichment_ThrowsError() async {
        let mock = MockContextualEnrichmentService(error: NSError(domain: "test", code: -1))
        
        do {
            let _ = try await mock.enrich(location: CLLocationCoordinate2D())
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual((error as NSError).code, -1)
        }
        
        XCTAssertEqual(mock.enrichLocationCallCount, 1)
    }
    
    func testMockContextualEnrichment_ReturnsNil() async throws {
        let mock = MockContextualEnrichmentService() // No data configured → returns nil
        
        let result = try await mock.enrich(location: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        
        XCTAssertNil(result, "Should return nil when no data configured")
        XCTAssertEqual(mock.enrichLocationCallCount, 1)
    }
    
    // MARK: - Link Enrichment Mock Tests
    
    func testMockLinkEnrichment_ReturnsData() async throws {
        let mockData = EnrichmentData(
            title: "Wikipedia",
            descriptionText: "Free encyclopedia",
            categories: ["Reference"],
            imageURL: URL(string: "https://wikipedia.org/logo.png")
        )
        let mock = MockLinkEnrichmentService(result: mockData)
        
        let result = try await mock.enrich(url: URL(string: "https://wikipedia.org")!)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Wikipedia")
        XCTAssertEqual(result?.descriptionText, "Free encyclopedia")
        XCTAssertEqual(mock.enrichCallCount, 1)
    }
    
    func testMockLinkEnrichment_ThrowsError() async {
        let mock = MockLinkEnrichmentService(error: URLError(.timedOut))
        
        do {
            let _ = try await mock.enrich(url: URL(string: "https://timeout.com")!)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
    
    func testMockLinkEnrichment_ReturnsNilForInvalidURL() async throws {
        let mock = MockLinkEnrichmentService() // nil result
        
        let result = try await mock.enrich(url: URL(string: "https://nothing.com")!)
        XCTAssertNil(result)
    }
    
    // MARK: - Foursquare API Key Guard
    
    func testFoursquareNoAPIKey_ReturnsNil() async throws {
        let service = FoursquareEnrichmentService(apiKey: nil)
        let location = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        
        let result = try await service.enrich(location: location)
        XCTAssertNil(result, "Should return nil when API key is missing")
    }
    
    // MARK: - Call Tracking
    
    func testMockTracksMultipleCalls() async throws {
        let mock = MockContextualEnrichmentService(
            locationResult: EnrichmentData(title: "Place")
        )
        
        for _ in 0..<5 {
            let _ = try await mock.enrich(location: CLLocationCoordinate2D())
        }
        
        XCTAssertEqual(mock.enrichLocationCallCount, 5)
    }
}
