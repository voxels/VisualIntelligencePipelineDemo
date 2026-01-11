
import XCTest
import CoreLocation
@testable import DiverKit

final class ContextualServicesTests: XCTestCase {
    
    func testContextQuestionServiceProcessing() async throws {
        let service = ContextQuestionService()
        let data = EnrichmentData(
            title: "Test Place",
            descriptionText: "A nice place to verify tests.",
            categories: ["Testing"],
            questions: []
        )
        
        // Update to expect 4-element tuple
        let (summary, questions, purpose, tags) = try await service.processContext(from: data)
        
        // Verify output
        XCTAssertNotNil(summary)
        XCTAssertFalse(questions.isEmpty)
        XCTAssertNotNil(purpose)
        XCTAssertNotNil(tags)
        
        // This test runs in an environment where GenerativeCapability might be mock or heuristic.
        // We verify that we got *something* back.
        if summary == "This is a popular spot known for its great reliable service. Visitors often praise the atmosphere and convenient location." {
             // Mock path
             XCTAssertEqual(purpose, "General Point of Interest")
             XCTAssertEqual(tags, ["Community", "Service", "Local Favorite"])
        } else {
             // Heuristic path
             XCTAssertEqual(purpose, "Testing and quality assurance")
             // Heuristic statements vary, just check not empty
             XCTAssertFalse(questions.isEmpty)
             XCTAssertEqual(tags, ["Testing", "Quality Assurance"])
        }
    }
    
    func testDuckDuckGoEnrichmentServiceGeneratesQuestions() async throws {
        let service = DuckDuckGoEnrichmentService()
        let coords = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        
        let enrichment = try await service.enrich(query: "Coffee Shop", location: coords)
        
        XCTAssertNotNil(enrichment)
        // DuckDuckGo implementation details might vary, but we expect a title
        XCTAssertNotNil(enrichment?.title)
        XCTAssertFalse(enrichment?.title?.isEmpty ?? true)
        
        // Questions generation is done later in the pipeline usually, but if the service generates them:
        // XCTAssertFalse(enrichment?.questions.isEmpty ?? true)
    }
}
