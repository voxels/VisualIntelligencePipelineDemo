import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

/// Tests for the freshness guard in `MetadataPipelineService.processItemByID`.
///
/// The guard prevents redundant reprocessing of items already handled by another
/// device via CloudKit sync. Items with `.ready` or `.processing` status are skipped
/// unless `force: true` is passed (used by the "Process Now" button).
@MainActor
final class ProcessItemFreshnessGuardTests: XCTestCase {

    var modelContainer: ModelContainer!
    var queueStore: DiverQueueStore!
    var tempURL: URL!
    var service: MetadataPipelineService!

    override func setUp() async throws {
        let unifiedDataManager = UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        let mainContext = unifiedDataManager.mainContext

        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        queueStore = try DiverQueueStore(directoryURL: tempURL)

        service = MetadataPipelineService(
            queueStore: queueStore,
            modelContainer: modelContainer,
            mainContext: mainContext
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }


    // MARK: - Skip .ready items (multi-device guard)

    /// When an item is `.ready`, `processItemByID` should skip it without modifying status.
    /// This models the scenario where CloudKit synced a `.ready` status from another device.
    func testSkipsReadyItemByDefault() async throws {
        // Given: an item already in .ready state
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = false
        let item = ProcessedItem(id: "ready-item", createdAt: Date(), status: .ready)
        item.summary = "Existing summary from device A"
        ctx.insert(item)
        try ctx.save()

        // When: processItemByID with default force=false
        try await service.processItemByID("ready-item")

        // Then: item should still be .ready — guard kicked in, no reprocessing
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "ready-item" })
        let found = try ctx.fetch(fetch)
        XCTAssertEqual(found.first?.status, .ready, "Guard should leave .ready item untouched")
        XCTAssertEqual(found.first?.summary, "Existing summary from device A", "Summary should be preserved")
    }

    // MARK: - Skip .processing items

    /// When an item is `.processing`, it's being handled right now (possibly on another device).
    /// `processItemByID` should skip it to avoid duplicate processing.
    func testSkipsProcessingItemByDefault() async throws {
        // Given: an item actively being processed (e.g., by another CloudKit-synced device)
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = false
        let item = ProcessedItem(id: "processing-item", createdAt: Date(), status: .processing)
        ctx.insert(item)
        try ctx.save()

        // When: processItemByID with default force=false
        try await service.processItemByID("processing-item")

        // Then: item should still be .processing — guard kicked in
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "processing-item" })
        let found = try ctx.fetch(fetch)
        XCTAssertEqual(found.first?.status, .processing, "Guard should leave .processing item untouched")
    }

    // MARK: - force=true bypasses the guard

    /// `force: true` is used by the "Process Now" button — it must bypass the freshness guard
    /// and actively reprocess even a .ready item.
    func testForceBypassesGuardOnReadyItem() async throws {
        // Given: an item in .ready state
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = false
        let item = ProcessedItem(id: "force-reprocess", createdAt: Date(), status: .ready)
        ctx.insert(item)
        try ctx.save()

        // When: processItemByID with force=true (simulates "Process Now" button).
        // The pipeline will attempt to run but won't have enrichment services —
        // it transitions the item OUT of .ready regardless (guard bypassed).
        try? await service.processItemByID("force-reprocess", force: true)

        // Then: processing log should show the item was touched by processItemByID
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "force-reprocess" })
        let found = try ctx.fetch(fetch)
        XCTAssertEqual(found.count, 1, "Item should still exist after force reprocess")
        let log = found.first?.processingLog ?? []
        let wasProcessed = log.contains(where: { $0.contains("Starting reprocessing via processItemByID") })
        XCTAssertTrue(wasProcessed, "force=true should bypass guard and begin reprocessing")
    }

    // MARK: - Queued items bypass the guard (intended for reprocessing)

    /// `.queued` items are the normal reprocessing trigger — they must NOT be skipped.
    func testQueuedItemsAreNotGuarded() async throws {
        // Given: an item in .queued state (set by reprocessPipeline Phase 1)
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = false
        let item = ProcessedItem(id: "queued-item", createdAt: Date(), status: .queued)
        ctx.insert(item)
        try ctx.save()

        // When: processItemByID with default force=false
        try? await service.processItemByID("queued-item")

        // Then: item should have been touched — status advanced past .queued
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "queued-item" })
        let found = try ctx.fetch(fetch)
        XCTAssertEqual(found.count, 1)
        XCTAssertNotEqual(found.first?.status, .queued, ".queued items should not be blocked by the freshness guard")
    }
}
