import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

@MainActor
final class LocalPipelineServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var service: LocalPipelineService!

    override func setUp() async throws {
        let unifiedDataManager = UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        modelContext = unifiedDataManager.mainContext
        service = LocalPipelineService(modelContext: modelContext)
    }

    func testProcessNewItemWithAttribution() async throws {
        // Given: A LocalInput and a descriptor with attributionID
        let input = LocalInput(url: "https://apple.com", source: "test")
        modelContext.insert(input)
        
        let descriptor = DiverItemDescriptor(
            id: "apple-id",
            url: "https://apple.com",
            title: "Apple",
            type: .web,
            attributionID: "sender-123"
        )

        // When: We process the input
        let processed = try await service.process(input: input, descriptor: descriptor)

        // Then: The ProcessedItem should have the attributionID and status .ready
        XCTAssertEqual(processed.attributionID, "sender-123")
        XCTAssertEqual(processed.status, .ready)
        XCTAssertEqual(processed.id, "apple-id")
        XCTAssertEqual(processed.title, "Apple")
    }

    func testProcessExistingItemUpdatesAttributionAndStatus() async throws {
        // Given: An existing ProcessedItem with status .queued
        let processedId = "existing-item"
        let existing = ProcessedItem(id: processedId, title: "Old Title", status: .queued)
        modelContext.insert(existing)
        
        let input = LocalInput(url: "https://example.com")
        modelContext.insert(input)

        let descriptor = DiverItemDescriptor(
            id: processedId,
            url: "https://example.com",
            title: "New Title",
            type: .web,
            attributionID: "new-attribution"
        )

        // When: We process the input for the existing ID
        let result = try await service.process(input: input, descriptor: descriptor)

        // Then: The item should be updated
        XCTAssertEqual(result.id, processedId)
        XCTAssertEqual(result.title, "New Title")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.attributionID, "new-attribution")
    }

    func testProcessWithoutDescriptorDerivesInfo() async throws {
        // Given: A LocalInput with a URL
        let input = LocalInput(url: "https://google.com")
        modelContext.insert(input)

        // When: We process without a descriptor
        let processed = try await service.process(input: input)

        // Then: It derives the ID and title from the URL
        XCTAssertEqual(processed.title, "google.com")
        XCTAssertFalse(processed.id.isEmpty)
        XCTAssertEqual(processed.status, .ready)
    }

    func testProcessDocumentItemWithPayload() async throws {
        // Given: A LocalInput with a document type and raw payload
        let testData = "test document image data".data(using: .utf8)!
        let input = LocalInput(
            url: "diver-doc://test",
            inputType: DiverItemType.document.rawValue,
            rawPayload: testData
        )
        modelContext.insert(input)

        let descriptor = DiverItemDescriptor(
            id: "test",
            url: "diver-doc://test",
            title: "Test Document",
            type: .document
        )

        // When: We process the input
        let processed = try await service.process(input: input, descriptor: descriptor)

        // Then: The ProcessedItem should have the same rawPayload
        XCTAssertEqual(processed.rawPayload, testData)
        XCTAssertEqual(processed.entityType, DiverItemType.document.rawValue)
        XCTAssertEqual(processed.title, "Test Document")
    }
}
