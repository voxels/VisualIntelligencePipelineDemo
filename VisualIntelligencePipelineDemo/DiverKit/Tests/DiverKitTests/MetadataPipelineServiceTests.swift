import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

@MainActor
final class MetadataPipelineServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var queueStore: DiverQueueStore!
    var service: MetadataPipelineService!
    var tempURL: URL!

    override func setUp() async throws {
        // Setup SwiftData (In-Memory) using UnifiedDataManager for consistency
        let unifiedDataManager = UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        modelContext = unifiedDataManager.mainContext

        // Setup QueueStore (Temp Dir)
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        queueStore = try DiverQueueStore(directoryURL: tempURL)

        // Setup Service
        service = MetadataPipelineService(queueStore: queueStore, modelContainer: modelContainer, mainContext: modelContext)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: tempURL)
    }

    func testProcessPendingQueueCreatesLocalInput() async throws {
        // Given: An item in the queue
        let descriptor = DiverItemDescriptor(
            id: UUID().uuidString,
            url: "https://example.com",
            title: "Test Item",
            type: .web,
            attributionID: "highlight-456"
        )
        let item = DiverQueueItem(action: "save", descriptor: descriptor)
        try queueStore.enqueue(item)

        // When: We process the queue
        // Note: processPendingQueue() internally uses Task.detached(priority: .utility),
        // so the await returns before processing is complete.
        try await service.processPendingQueue()
        
        // Wait for the background task to drain the queue
        var retries = 0
        while retries < 30 {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            let remaining = try queueStore.pendingEntries()
            if remaining.isEmpty { break }
            retries += 1
        }

        // Then: The queue should be empty (background task should have consumed it)
        let pending = try queueStore.pendingEntries()
        XCTAssertTrue(pending.isEmpty, "Queue should be drained after processing")

        // And: A ProcessedItem should exist in a fresh context
        // (background processing writes to a separate ModelContext)
        let freshCtx = ModelContext(modelContainer)
        freshCtx.autosaveEnabled = false
        let processedDetails = FetchDescriptor<ProcessedItem>()
        let items = try freshCtx.fetch(processedDetails)
        XCTAssertEqual(items.count, 1, "Should have created 1 ProcessedItem")
        XCTAssertEqual(items.first?.url, "https://example.com")
        XCTAssertEqual(items.first?.entityType, "web")
    }

}
