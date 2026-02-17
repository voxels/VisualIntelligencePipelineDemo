
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
        // LLM output is non-deterministic, so we verify we got *something* back
        // rather than checking exact strings.
        XCTAssertFalse(purpose?.isEmpty ?? true, "Purpose should not be empty")
        XCTAssertFalse(tags.isEmpty, "Tags should not be empty")
        XCTAssertFalse(questions.isEmpty, "Questions should not be empty")
    }

    func testLargeContextSummarization() async throws {
        let service = ContextQuestionService()
        
        // Generate a large string > 12k chars
        let largeDescription = String(repeating: "This is a long sentence repeated to test context limits. ", count: 500) // approx 27k chars
        
        let data = EnrichmentData(
            title: "Large Context Test",
            descriptionText: largeDescription,
            categories: ["Testing"],
            questions: []
        )
        
        // This should NOT throw exceededContextWindowSize
        let (summary, _, purpose, _) = try await service.processContext(from: data)
        
        XCTAssertNotNil(summary)
        // Ensure we got a summary back (even if it's the fallback description prefix in mock mode)
        XCTAssertFalse(summary?.isEmpty ?? true)
        
        // Verify purpose generation also survives
        let suggestions = try await service.suggestPurposes(from: largeDescription)
        // In mock mode it returns empty, but primarily we want to ensure it doesn't crash/throw
        // If real model is present, it returns 3-5 purposes
    }
    
    func testDuckDuckGoEnrichment() async throws {
        let service = DuckDuckGoEnrichmentService()
        let coords = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // NYC for test
        
        let enrichment = try await service.enrich(query: "Coffee Shop", location: coords)
        
        XCTAssertNotNil(enrichment)
        // DuckDuckGo implementation details might vary, but we expect a title
        XCTAssertNotNil(enrichment?.title)
        XCTAssertFalse(enrichment?.title?.isEmpty ?? true)
        
        // Questions generation is done later in the pipeline usually, but if the service generates them:
        // XCTAssertFalse(enrichment?.questions.isEmpty ?? true)
    }

}
