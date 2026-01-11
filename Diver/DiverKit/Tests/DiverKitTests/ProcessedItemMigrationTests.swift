import XCTest
import SwiftData
@testable import DiverKit

final class ProcessedItemMigrationTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([ProcessedItem.self, LocalInput.self, UserConcept.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - Migration Default Values Tests

    func testNewFieldsHaveDefaultValues() throws {
        // Create an item (simulating pre-migration record without new fields)
        let item = ProcessedItem(
            id: "migration-test-id",
            url: "https://example.com",
            title: "Migration Test"
        )

        // Verify new fields have default values
        XCTAssertEqual(item.status, .queued, "Default status should be .queued")
        XCTAssertNil(item.source, "Default source should be nil")
        XCTAssertNotNil(item.updatedAt, "updatedAt should be set")
        XCTAssertEqual(item.referenceCount, 0, "Default referenceCount should be 0")
        XCTAssertNil(item.lastProcessedAt, "Default lastProcessedAt should be nil")
        XCTAssertNil(item.wrappedLink, "Default wrappedLink should be nil")
        XCTAssertNil(item.payloadRef, "Default payloadRef should be nil")
    }

    func testExistingFieldsPreservedAfterMigration() throws {
        // Create item with original fields
        let originalId = "preserved-id"
        let originalUrl = "https://example.com/preserved"
        let originalTitle = "Preserved Title"
        let originalSummary = "Preserved Summary"
        let originalTags = ["tag1", "tag2"]
        let originalCreatedAt = Date().addingTimeInterval(-86400) // 1 day ago

        let item = ProcessedItem(
            id: originalId,
            url: originalUrl,
            title: originalTitle,
            summary: originalSummary,
            tags: originalTags,
            createdAt: originalCreatedAt
        )

        modelContext.insert(item)
        try modelContext.save()

        // Fetch the item
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == originalId }
        )
        let fetchedItems = try modelContext.fetch(descriptor)

        XCTAssertEqual(fetchedItems.count, 1, "Should fetch exactly one item")

        guard let fetchedItem = fetchedItems.first else {
            XCTFail("Failed to fetch item")
            return
        }

        // Verify original fields are preserved
        XCTAssertEqual(fetchedItem.id, originalId)
        XCTAssertEqual(fetchedItem.url, originalUrl)
        XCTAssertEqual(fetchedItem.title, originalTitle)
        XCTAssertEqual(fetchedItem.summary, originalSummary)
        XCTAssertEqual(fetchedItem.tags, originalTags)

        // Verify new fields have defaults
        XCTAssertEqual(fetchedItem.status, .queued)
        XCTAssertEqual(fetchedItem.referenceCount, 0)
    }

    func testUpdateNewFieldsAfterMigration() throws {
        // Create an item
        let item = ProcessedItem(id: "update-test-id", url: "https://example.com")
        modelContext.insert(item)
        try modelContext.save()

        // Update new fields
        item.status = .ready
        item.source = "test-source"
        item.referenceCount = 5
        item.lastProcessedAt = Date()
        item.wrappedLink = "https://secretatomics.com/w/abc123"
        item.payloadRef = "payload-ref-456"

        try modelContext.save()

        // Fetch and verify
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "update-test-id" }
        )
        let fetchedItems = try modelContext.fetch(descriptor)

        guard let fetchedItem = fetchedItems.first else {
            XCTFail("Failed to fetch item")
            return
        }

        XCTAssertEqual(fetchedItem.status, .ready)
        XCTAssertEqual(fetchedItem.source, "test-source")
        XCTAssertEqual(fetchedItem.referenceCount, 5)
        XCTAssertNotNil(fetchedItem.lastProcessedAt)
        XCTAssertEqual(fetchedItem.wrappedLink, "https://secretatomics.com/w/abc123")
        XCTAssertEqual(fetchedItem.payloadRef, "payload-ref-456")
    }

    func testQueryByNewStatusField() throws {
        // Insert multiple items with different statuses
        let readyItem = ProcessedItem(id: "ready-1", status: ProcessingStatus.ready)
        let queuedItem = ProcessedItem(id: "queued-1", status: ProcessingStatus.queued)
        let processingItem = ProcessedItem(id: "processing-1", status: ProcessingStatus.processing)
        let failedItem = ProcessedItem(id: "failed-1", status: ProcessingStatus.failed)

        modelContext.insert(readyItem)
        modelContext.insert(queuedItem)
        modelContext.insert(processingItem)
        modelContext.insert(failedItem)
        try modelContext.save()

        // Fetch all and filter manually (SwiftData enum predicates have limitations)
        let allItems = try modelContext.fetch(FetchDescriptor<ProcessedItem>())

        let readyItems = allItems.filter { $0.status == .ready }
        XCTAssertEqual(readyItems.count, 1)
        XCTAssertEqual(readyItems.first?.id, "ready-1")

        let queuedItems = allItems.filter { $0.status == .queued }
        XCTAssertEqual(queuedItems.count, 1)
        XCTAssertEqual(queuedItems.first?.id, "queued-1")

        let failedItems = allItems.filter { $0.status == .failed }
        XCTAssertEqual(failedItems.count, 1)
        XCTAssertEqual(failedItems.first?.id, "failed-1")
    }

    func testSortByUpdatedAt() throws {
        let now = Date()
        let item1 = ProcessedItem(id: "item-1", updatedAt: now.addingTimeInterval(-300))
        let item2 = ProcessedItem(id: "item-2", updatedAt: now.addingTimeInterval(-600))
        let item3 = ProcessedItem(id: "item-3", updatedAt: now)

        modelContext.insert(item1)
        modelContext.insert(item2)
        modelContext.insert(item3)
        try modelContext.save()

        // Fetch sorted by updatedAt descending
        let descriptor = FetchDescriptor<ProcessedItem>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let sortedItems = try modelContext.fetch(descriptor)

        XCTAssertEqual(sortedItems.count, 3)
        XCTAssertEqual(sortedItems[0].id, "item-3") // Most recent
        XCTAssertEqual(sortedItems[1].id, "item-1")
        XCTAssertEqual(sortedItems[2].id, "item-2") // Oldest
    }
}
