import XCTest
import SwiftData
@testable import DiverKit

@MainActor
final class ReprocessPipelineFilteringTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var service: LocalPipelineService!

    override func setUp() async throws {
        let schema = Schema([ProcessedItem.self, SessionMetadata.self, SessionCollection.self, UserConcept.self, LocalInput.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)
        
        // Initialize MetadataPipelineService and register in Services.shared
        // reprocessPipeline now depends on it.
        let metadataPipeline = MetadataPipelineService(
            queueStore: nil,
            modelContainer: modelContainer,
            mainContext: modelContext
        )
        Services.shared.metadataPipelineService = metadataPipeline
        
        service = LocalPipelineService(modelContext: modelContext)
    }

    func testReprocessPipelineRespectsCutoffDateForQueueClearing() async throws {
        // Given: 
        // 1. A failed item from 1 month ago (SHOULD NOT be cleared)
        let oldDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let oldItem = ProcessedItem(id: "old-failed", createdAt: oldDate, status: .failed)
        modelContext.insert(oldItem)
        
        // 2. A failed item from today (SHOULD be cleared/reprocessed)
        let today = Date()
        let newItem = ProcessedItem(id: "new-failed", createdAt: today, status: .failed)
        modelContext.insert(newItem)
        
        try modelContext.save()
        
        // When: Reprocessing with cutoff set to "Today"
        let cutoff = Calendar.current.startOfDay(for: today)
        try await service.reprocessPipeline(cutoffDate: cutoff)
        
        // Then:
        // 1. Old item should still exist and still be "failed"
        let oldFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "old-failed" })
        let oldItems = try modelContext.fetch(oldFetch)
        XCTAssertEqual(oldItems.count, 1)
        XCTAssertEqual(oldItems.first?.status, .failed, "Old failed item should not have been cleared")
        
        // 2. New item should have been reprocessed. 
        let newFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "new-failed" })
        let newItems = try modelContext.fetch(newFetch)
        XCTAssertEqual(newItems.count, 1)
        XCTAssertNotEqual(newItems.first?.status, .failed, "New failed item should have been reprocessed or reset to queued")
    }

    func testReprocessPipelinePreservesSessionID() async throws {
        // Given: An item with a specific session ID that is in 'failed' state
        let sessionID = "persistent-session-123"
        let item = ProcessedItem(id: "item-to-reprocess", createdAt: Date(), status: .failed)
        item.sessionID = sessionID
        modelContext.insert(item)
        try modelContext.save()
        
        // When: Reprocessing
        try await service.reprocessPipeline(cutoffDate: Date().addingTimeInterval(-3600))
        
        // Then: The item should still have the same session ID
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "item-to-reprocess" })
        let items = try modelContext.fetch(fetch)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sessionID, sessionID, "Session ID should be preserved during reprocessing")
    }
}
