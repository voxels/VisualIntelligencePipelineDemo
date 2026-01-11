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
        service = MetadataPipelineService(queueStore: queueStore, modelContext: modelContext)
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
        try await service.processPendingQueue()

        // Then: The queue should be empty
        let pending = try queueStore.pendingEntries()
        XCTAssertTrue(pending.isEmpty)

        // And: A LocalInput should exist in SwiftData
        let descriptorDetails = FetchDescriptor<LocalInput>()
        let inputs = try modelContext.fetch(descriptorDetails)
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs.first?.url, "https://example.com")
        XCTAssertEqual(inputs.first?.inputType, "web")
    }
}
