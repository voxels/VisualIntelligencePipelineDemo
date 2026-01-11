import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

@MainActor
final class LinkEnrichmentServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var service: LocalPipelineService!

    override func setUp() async throws {
        let unifiedDataManager = UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        modelContext = unifiedDataManager.mainContext
        service = LocalPipelineService(modelContext: modelContext)
    }

    func testEnrichmentUpdatesProcessedItem() async throws {
        // Given: A LocalInput and a Mock enrichment service
        let urlString = "https://restaurant.com"
        let input = LocalInput(url: urlString)
        modelContext.insert(input)
        
        let mockEnrichment = LinkMockEnrichmentService(data: EnrichmentData(
            title: "Fancy Restaurant",
            descriptionText: "Amazing food",
            categories: ["Dinner"],
            location: "Downtown",
            rating: 4.5
        ))

        // When: We process with enrichment
        let processed = try await service.process(input: input, enrichmentService: mockEnrichment)

        // Then: The ProcessedItem should have the enrichment data
        XCTAssertEqual(processed.title, "Fancy Restaurant")
        XCTAssertEqual(processed.summary, "Amazing food")
        XCTAssertTrue(processed.tags.contains("Dinner"))
        XCTAssertEqual(processed.location, "Downtown")
        XCTAssertEqual(processed.rating, 4.5)
    }

    func testEnrichmentDoesNotOverwriteExistingData() async throws {
        // Given: An existing ProcessedItem with some data
        let urlString = "https://restaurant.com"
        let processedId = DiverLinkWrapper.id(for: URL(string: urlString)!)
        let existing = ProcessedItem(id: processedId, url: urlString, title: "Original Title")
        existing.tags = ["OriginalTag"]
        modelContext.insert(existing)
        
        let input = LocalInput(url: urlString)
        modelContext.insert(input)
        
        let mockEnrichment = LinkMockEnrichmentService(data: EnrichmentData(
            title: "New Title",
            descriptionText: "New Description",
            categories: ["NewCategory"],
            rating: 5.0
        ))

        // When: We process with enrichment
        let result = try await service.process(input: input, enrichmentService: mockEnrichment)

        // Then: The title should NOT be overwritten because it was already present
        XCTAssertEqual(result.title, "Original Title")
        // But missing data should be added
        XCTAssertEqual(result.summary, "New Description")
        XCTAssertEqual(result.rating, 5.0)
        // And tags should be merged
        XCTAssertTrue(result.tags.contains("OriginalTag"))
        XCTAssertTrue(result.tags.contains("NewCategory"))
    }
}

private struct LinkMockEnrichmentService: LinkEnrichmentService, @unchecked Sendable {
    let data: EnrichmentData?
    
    func enrich(url: URL) async throws -> EnrichmentData? {
        return data
    }
}
