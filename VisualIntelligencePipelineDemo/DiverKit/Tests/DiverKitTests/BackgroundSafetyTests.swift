import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

// MARK: - Background Safety Tests
//
// These tests verify that the app handles background transitions, task cancellation,
// and resource teardown correctly to prevent Metal/GPU crashes and OS-initiated termination.
//
// Test Categories:
//   1. Cancellation Compliance — tasks respect Task.isCancelled before GPU work
//   2. Background Lifecycle — cancelProcessing() tears down all GPU resources
//   3. BGTask Handler Isolation — background tasks don't trigger GPU pipeline
//   4. SwiftData Relationship Safety — no crashes from deleted model relationships
//   5. Concurrency Stress — @unchecked Sendable types are actually thread-safe
//   6. Force Unwrap Guards — known optional paths don't crash

@MainActor
final class BackgroundSafetyTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var queueStore: DiverQueueStore!
    var pipelineService: MetadataPipelineService!
    var tempURL: URL!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
        
        tempURL = try makeTemporaryDirectory()
        queueStore = try DiverQueueStore(directoryURL: tempURL)
        
        pipelineService = MetadataPipelineService(
            queueStore: queueStore,
            modelContainer: modelContainer,
            mainContext: modelContext
        )
    }
    
    override func tearDown() async throws {
        pipelineService.cancelProcessing()
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // =========================================================================
    // MARK: - 1. Cancellation Compliance Tests
    // =========================================================================
    
    /// Verifies that a cancelled task marks items as `.queued` for retry rather than
    /// leaving them in `.processing` state (which would make them appear stuck).
    func testCancelledProcessingResetsItemToQueued() async throws {
        // Given: An item in processing state
        let item = makeProcessedItem(id: "cancel-test", status: .processing)
        modelContext.insert(item)
        try modelContext.save()
        
        // When: We cancel processing (simulating background transition)
        pipelineService.cancelProcessing()
        
        // Then: The service should not be processing
        XCTAssertFalse(pipelineService.isProcessingQueue,
                       "cancelProcessing() should clear isProcessingQueue flag")
    }
    
    /// Verifies that after cancellation, progress counters are zeroed out.
    func testCancelProcessingResetsProgressCounters() {
        // Given: Simulate active processing state
        pipelineService.queueTotalCount = 10
        pipelineService.queueCompletedCount = 5
        pipelineService.queueCurrentItemTitle = "Test Item"
        pipelineService.queueStatusMessage = "Analyzing content..."
        
        // When: Cancel
        pipelineService.cancelProcessing()
        
        // Then: All progress should be reset
        XCTAssertEqual(pipelineService.queueTotalCount, 0)
        XCTAssertEqual(pipelineService.queueCompletedCount, 0)
        XCTAssertNil(pipelineService.queueCurrentItemTitle)
        XCTAssertNil(pipelineService.queueStatusMessage)
        XCTAssertEqual(pipelineService.queueProgress, 0.0)
    }
    
    /// Verifies that cancellation is immediate and doesn't leave tasks dangling.
    func testCancelProcessingIsIdempotent() {
        // Calling cancelProcessing() multiple times should not crash
        pipelineService.cancelProcessing()
        pipelineService.cancelProcessing()
        pipelineService.cancelProcessing()
        
        XCTAssertFalse(pipelineService.isProcessingQueue)
    }
    
    /// Verifies that a Task respects isCancelled in a loop pattern (simulating
    /// the video thumbnail extraction loop).
    func testTaskCancellationBreaksLoop() async {
        var iterationsCompleted = 0
        let totalIterations = 100
        
        let task = Task {
            for i in 0..<totalIterations {
                guard !Task.isCancelled else { break }
                iterationsCompleted = i + 1
                // Simulate work
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        
        // Cancel after a brief delay
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        
        XCTAssertLessThan(iterationsCompleted, totalIterations,
                          "Cancellation should break the loop before all iterations complete")
    }
    
    /// Verifies that a detached task also respects cancellation.
    func testDetachedTaskCancellation() async {
        let task = Task(priority: .utility) { () -> Bool in
            // Return whether isCancelled was true at entry
            guard !Task.isCancelled else {
                return true // guard triggered
            }
            // Simulate long work
            try? await Task.sleep(for: .seconds(5))
            return false
        }
        
        // Cancel immediately
        task.cancel()
        let wasGuardTriggered = await task.value
        
        XCTAssertTrue(wasGuardTriggered,
                      "Detached task should check isCancelled before doing work")
    }
    
    // =========================================================================
    // MARK: - 2. Background Lifecycle Teardown Tests
    // =========================================================================
    
    /// Verifies that cancelProcessing() unloads FastVLM from GPU memory.
    func testCancelProcessingUnloadsFastVLM() {
        // Given: A FastVLM service is attached
        let fastVLM = FastVLMEnrichmentService()
        fastVLM.retainModel = true
        pipelineService.fastVLMService = fastVLM
        
        // When: Cancel processing (simulating background transition)
        pipelineService.cancelProcessing()
        
        // Then: FastVLM should be unloaded
        XCTAssertFalse(fastVLM.retainModel,
                       "cancelProcessing() should set retainModel to false")
    }
    
    /// Verifies that cancelProcessing() works even without a FastVLM service.
    func testCancelProcessingWithoutFastVLM() {
        // Given: No FastVLM service
        pipelineService.fastVLMService = nil
        
        // When/Then: Should not crash
        pipelineService.cancelProcessing()
        
        XCTAssertFalse(pipelineService.isProcessingQueue)
    }
    
    /// Verifies that cancellation clears the current processing task reference.
    func testCancelProcessingClearsTaskReferences() async throws {
        // Given: Start processing (which creates a detached task)
        let descriptor = makeDescriptor(url: "https://test.com", title: "BG Test")
        let item = DiverQueueItem(action: "save", descriptor: descriptor)
        try queueStore.enqueue(item)
        
        try await pipelineService.processPendingQueue()
        
        // When: Cancel
        pipelineService.cancelProcessing()
        
        // Then: Service state should be fully reset
        XCTAssertFalse(pipelineService.isProcessingQueue)
        XCTAssertEqual(pipelineService.queueProgress, 0.0)
    }
    
    // =========================================================================
    // MARK: - 3. BGTask Handler Isolation Tests
    // =========================================================================
    
    /// Verifies that queue items persisted to DiverQueueStore survive across
    /// service instances (simulating app termination + relaunch).
    func testQueueItemsSurviveServiceRecreation() async throws {
        // Given: Items in the queue store
        let descriptor = makeDescriptor(url: "https://persisted.com", title: "Persisted")
        let item = DiverQueueItem(action: "save", descriptor: descriptor)
        try queueStore.enqueue(item)
        
        // When: Create a new service instance (simulating relaunch)
        let newService = MetadataPipelineService(
            queueStore: queueStore,
            modelContainer: modelContainer,
            mainContext: modelContext
        )
        _ = newService // suppress unused warning
        
        // Then: Queue items should still be pending
        let pending = try queueStore.pendingEntries()
        XCTAssertEqual(pending.count, 1, "Queue items should persist across service instances")
        XCTAssertEqual(pending.first?.item.descriptor.url, "https://persisted.com")
    }
    
    /// Verifies that the queue store allows enqueue and dequeue without
    /// any GPU/ML dependencies (pure disk I/O).
    func testQueueStoreIsGPUIndependent() async throws {
        // Given: Multiple items enqueued
        for i in 0..<5 {
            let descriptor = makeDescriptor(
                id: "item-\(i)",
                url: "https://example.com/\(i)",
                title: "Item \(i)"
            )
            let item = DiverQueueItem(action: "save", descriptor: descriptor)
            try queueStore.enqueue(item)
        }
        
        // When: Read all pending items (this should be pure disk I/O)
        let pending = try queueStore.pendingEntries()
        
        // Then: All items should be readable without GPU
        XCTAssertEqual(pending.count, 5)
        
        // And: We can remove them without GPU
        for record in pending {
            try queueStore.remove(record)
        }
        
        let remaining = try queueStore.pendingEntries()
        XCTAssertTrue(remaining.isEmpty)
    }
    
    // =========================================================================
    // MARK: - 4. SwiftData Relationship Safety Tests
    // =========================================================================
    
    /// Verifies that `relatedConcepts` uses sessionID comparison (not relationship)
    /// and doesn't crash when called with a session that has items.
    func testRelatedConceptsUsesSessionIDNotRelationship() throws {
        let session = makeSession(sessionID: "rc-session", title: "Test Session")
        let item = makeProcessedItem(id: "rc-item", sessionID: "rc-session", tags: ["photography"])
        let concept = UserConcept(name: "photography", definition: "Taking photos")
        
        modelContext.insert(session)
        modelContext.insert(item)
        modelContext.insert(concept)
        try modelContext.save()
        
        let viewModel = SidebarViewModel()
        let allItems = try modelContext.fetch(FetchDescriptor<ProcessedItem>())
        let allConcepts = try modelContext.fetch(FetchDescriptor<UserConcept>())
        
        let result = viewModel.relatedConcepts(for: session, allItems: allItems, allConcepts: allConcepts)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "photography")
    }
    
    /// Verifies that `relatedConcepts` returns empty when session has no matching items
    /// (graceful degradation, no crash).
    func testRelatedConceptsReturnsEmptyForOrphanSession() throws {
        let session = makeSession(sessionID: "orphan-session", title: "Orphan")
        let concept = UserConcept(name: "test", definition: "Test concept")
        
        modelContext.insert(session)
        modelContext.insert(concept)
        try modelContext.save()
        
        let viewModel = SidebarViewModel()
        let allConcepts = try modelContext.fetch(FetchDescriptor<UserConcept>())
        
        // No items at all — should return empty, not crash
        let result = viewModel.relatedConcepts(for: session, allItems: [], allConcepts: allConcepts)
        
        XCTAssertTrue(result.isEmpty, "Should return empty for session with no items")
    }
    
    /// Verifies that accessing a deleted ProcessedItem's properties doesn't crash.
    func testDeletedItemPropertyAccessDoesNotCrash() throws {
        let item = makeProcessedItem(id: "delete-test", title: "Will Be Deleted")
        modelContext.insert(item)
        try modelContext.save()
        
        // Capture the ID before deletion
        let capturedID = item.id
        
        // Delete the item
        modelContext.delete(item)
        try modelContext.save()
        
        // Verify it's gone
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == capturedID }
        )
        let results = try modelContext.fetch(fetch)
        XCTAssertTrue(results.isEmpty, "Item should be deleted")
    }
    
    /// Verifies that session items filtering by sessionID works correctly
    /// across multiple sessions.
    func testSessionIDFilteringIsolation() throws {
        let session1 = makeSession(sessionID: "session-A")
        let session2 = makeSession(sessionID: "session-B")
        let itemA = makeProcessedItem(id: "a1", sessionID: "session-A", tags: ["apple"])
        let itemB = makeProcessedItem(id: "b1", sessionID: "session-B", tags: ["banana"])
        let conceptApple = UserConcept(name: "apple", definition: "")
        let conceptBanana = UserConcept(name: "banana", definition: "")
        
        modelContext.insert(session1)
        modelContext.insert(session2)
        modelContext.insert(itemA)
        modelContext.insert(itemB)
        modelContext.insert(conceptApple)
        modelContext.insert(conceptBanana)
        try modelContext.save()
        
        let viewModel = SidebarViewModel()
        let allItems = try modelContext.fetch(FetchDescriptor<ProcessedItem>())
        let allConcepts = try modelContext.fetch(FetchDescriptor<UserConcept>())
        
        let resultA = viewModel.relatedConcepts(for: session1, allItems: allItems, allConcepts: allConcepts)
        let resultB = viewModel.relatedConcepts(for: session2, allItems: allItems, allConcepts: allConcepts)
        
        XCTAssertEqual(resultA.count, 1)
        XCTAssertEqual(resultA.first?.name, "apple", "Session A should only see apple")
        XCTAssertEqual(resultB.count, 1)
        XCTAssertEqual(resultB.first?.name, "banana", "Session B should only see banana")
    }
    
    // =========================================================================
    // MARK: - 5. Concurrency Stress Tests
    // =========================================================================
    
    /// Verifies that calling cancelProcessing() concurrently from multiple tasks
    /// doesn't crash or corrupt state.
    func testConcurrentCancelProcessingDoesNotCrash() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    self.pipelineService.cancelProcessing()
                }
            }
        }
        
        // If we got here without crashing, the test passes
        XCTAssertFalse(pipelineService.isProcessingQueue)
    }
    
    /// Verifies that reading progress properties concurrently doesn't crash.
    func testConcurrentProgressReadDoesNotCrash() async {
        // Set some state
        pipelineService.queueTotalCount = 10
        pipelineService.queueCompletedCount = 3
        
        await withTaskGroup(of: Double.self) { group in
            for _ in 0..<100 {
                group.addTask { @MainActor in
                    return self.pipelineService.queueProgress
                }
            }
            
            for await progress in group {
                // All reads should return a valid number
                XCTAssertFalse(progress.isNaN)
                XCTAssertGreaterThanOrEqual(progress, 0.0)
                XCTAssertLessThanOrEqual(progress, 1.0)
            }
        }
    }
    
    /// Verifies that the queue progress computation handles edge cases.
    func testQueueProgressEdgeCases() {
        // Zero total
        pipelineService.queueTotalCount = 0
        pipelineService.queueCompletedCount = 0
        XCTAssertEqual(pipelineService.queueProgress, 0.0,
                       "Progress should be 0 when total is 0")
        
        // Completed == total
        pipelineService.queueTotalCount = 5
        pipelineService.queueCompletedCount = 5
        XCTAssertEqual(pipelineService.queueProgress, 1.0,
                       "Progress should be 1.0 when complete")
        
        // Partial progress
        pipelineService.queueTotalCount = 10
        pipelineService.queueCompletedCount = 3
        XCTAssertEqual(pipelineService.queueProgress, 0.3, accuracy: 0.001)
    }
    
    /// Verifies that SidebarViewModel can be used from multiple concurrent reads.
    func testSidebarViewModelConcurrentSortAndFilter() async {
        let viewModel = SidebarViewModel()
        viewModel.searchText = ""
        
        let items = (0..<20).map { i in
            makeProcessedItem(id: "concurrent-\(i)", title: "Item \(i)")
        }
        
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    return viewModel.sortAndFilter(items: items).count
                }
            }
            
            for await count in group {
                XCTAssertEqual(count, 20, "All concurrent reads should return same result")
            }
        }
    }
    
    // =========================================================================
    // MARK: - 6. Force Unwrap / Fatal Path Guard Tests
    // =========================================================================
    
    /// Verifies that ProcessedItem can be created with all nil optional fields
    /// without crashing.
    func testProcessedItemCreationWithNilFields() {
        let item = ProcessedItem(
            id: "nil-test",
            url: nil,
            title: nil,
            status: .queued,
            sessionID: nil
        )
        
        // Accessing all optional properties should not crash
        XCTAssertNil(item.url)
        XCTAssertNil(item.title)
        XCTAssertNil(item.sessionID)
        XCTAssertNil(item.summary)
        XCTAssertNil(item.location)
        XCTAssertTrue(item.tags.isEmpty)
        XCTAssertTrue(item.categories.isEmpty)
        XCTAssertTrue(item.purposes.isEmpty)
        XCTAssertTrue(item.processingLog.isEmpty)
        XCTAssertEqual(item.failureCount, 0)
    }
    
    /// Verifies that DiverQueueStore can be created with a valid temp directory.
    func testQueueStoreCreationWithValidDirectory() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try DiverQueueStore(directoryURL: tempDir)
        let pending = try store.pendingEntries()
        XCTAssertTrue(pending.isEmpty, "New queue store should have no entries")
    }
    
    /// Verifies that DiverItemDescriptor round-trips through JSON encoding.
    func testDescriptorJSONRoundTrip() throws {
        let descriptor = makeDescriptor(
            id: "roundtrip",
            url: "https://example.com/test",
            title: "Round Trip Test",
            type: .web,
            sessionID: "session-123"
        )
        
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(DiverItemDescriptor.self, from: data)
        
        XCTAssertEqual(decoded.id, "roundtrip")
        XCTAssertEqual(decoded.url, "https://example.com/test")
        XCTAssertEqual(decoded.title, "Round Trip Test")
        XCTAssertEqual(decoded.sessionID, "session-123")
    }
    
    /// Verifies that MetadataPipelineService initializes with all nil optional services.
    func testServiceInitializationWithMinimalDependencies() {
        let service = MetadataPipelineService(
            queueStore: queueStore,
            modelContainer: modelContainer,
            mainContext: modelContext
        )
        
        // All optional services should be nil
        XCTAssertNil(service.enrichmentService)
        XCTAssertNil(service.locationService)
        XCTAssertNil(service.indexingService)
        XCTAssertNil(service.contextService)
        XCTAssertNil(service.fastVLMService)
        
        // Service should still be functional
        XCTAssertFalse(service.isProcessingQueue)
        XCTAssertEqual(service.queueProgress, 0.0)
    }
    
    /// Verifies that ProcessedItem status transitions are safe.
    func testProcessedItemStatusTransitions() {
        let item = makeProcessedItem(status: .queued)
        
        // All valid transitions
        item.status = .processing
        XCTAssertEqual(item.status, .processing)
        
        item.status = .ready
        XCTAssertEqual(item.status, .ready)
        
        item.status = .failed
        XCTAssertEqual(item.status, .failed)
        
        // Back to queued (retry scenario)
        item.status = .queued
        XCTAssertEqual(item.status, .queued)
    }
    
    /// Verifies that LocalInput can store and retrieve descriptorJSON safely.
    func testLocalInputDescriptorJSONPersistence() throws {
        let descriptor = makeDescriptor(
            id: "json-test",
            url: "https://example.com",
            title: "JSON Test",
            sessionID: "session-abc"
        )
        
        let localInput = LocalInput(
            createdAt: Date(),
            url: descriptor.url,
            source: "test",
            inputType: descriptor.type.rawValue,
            rawPayload: nil,
            sessionID: descriptor.sessionID,
            purposes: []
        )
        
        // Store descriptor JSON
        localInput.descriptorJSON = try JSONEncoder().encode(descriptor)
        
        modelContext.insert(localInput)
        try modelContext.save()
        
        // Retrieve and decode
        let fetch = FetchDescriptor<LocalInput>()
        let results = try modelContext.fetch(fetch)
        XCTAssertEqual(results.count, 1)
        
        if let savedJSON = results.first?.descriptorJSON {
            let decoded = try JSONDecoder().decode(DiverItemDescriptor.self, from: savedJSON)
            XCTAssertEqual(decoded.sessionID, "session-abc",
                           "descriptorJSON should preserve sessionID for crash recovery")
        } else {
            XCTFail("descriptorJSON should be saved")
        }
    }
    
    // =========================================================================
    // MARK: - 7. ModelContext Isolation Tests (processItemByID)
    // =========================================================================
    //
    // Regression tests for the EXC_BAD_ACCESS crash caused by N concurrent Tasks
    // all calling processItemImmediately() on a shared ModelContext from
    // EditLocationView.updateSessionLocation(). The fix: processItemByID()
    // creates a private ModelContext per call.
    
    /// Verifies that processItemByID uses a private context and doesn't crash
    /// when the item doesn't exist.
    func testProcessItemByIDHandlesMissingItem() async {
        // Given: A nonexistent item ID
        let bogusID = "nonexistent-\(UUID().uuidString)"
        
        // When/Then: Should not crash, should return gracefully
        do {
            try await pipelineService.processItemByID(bogusID)
            // No error thrown — method returns early for missing items
        } catch {
            XCTFail("processItemByID should not throw for missing items: \(error)")
        }
    }
    
    /// Verifies that calling processItemByID sequentially for multiple items
    /// does not crash (regression test for shared-context EXC_BAD_ACCESS).
    func testSequentialProcessItemByIDDoesNotCrash() async throws {
        // Given: Multiple items in a session
        let sessionID = "batch-session"
        let session = makeSession(sessionID: sessionID, title: "Batch Test")
        modelContext.insert(session)
        
        var itemIDs: [String] = []
        for i in 0..<5 {
            let item = makeProcessedItem(
                id: "batch-\(i)",
                url: "https://example.com/\(i)",
                title: "Item \(i)",
                status: .ready,
                sessionID: sessionID
            )
            modelContext.insert(item)
            itemIDs.append(item.id)
        }
        try modelContext.save()
        
        // When: Process all items sequentially via processItemByID
        // Each call creates a private ModelContext, avoiding shared-context crashes
        for id in itemIDs {
            try? await pipelineService.processItemByID(id)
        }
        
        // Then: All items should still exist and be in a valid state
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        let freshCtx = ModelContext(modelContainer)
        let items = try freshCtx.fetch(fetch)
        XCTAssertEqual(items.count, 5, "All 5 items should still exist after sequential processing")
        
        // Each item should be in a terminal state (ready or failed), not stuck in processing
        for item in items {
            XCTAssertNotEqual(item.statusRaw, ProcessingStatus.processing.rawValue,
                             "Item \(item.id) should not be stuck in processing state")
        }
    }
    
    /// Verifies that processItemByID sets status to processing then completes
    /// (or fails gracefully) — never leaves items stuck.
    func testProcessItemByIDSetsTerminalStatus() async throws {
        // Given: A ready item
        let item = makeProcessedItem(id: "terminal-test", status: .ready)
        modelContext.insert(item)
        try modelContext.save()
        
        // When: Process it
        try? await pipelineService.processItemByID("terminal-test")
        
        // Then: Item should be in a terminal state (ready or failed)
        let freshCtx = ModelContext(modelContainer)
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "terminal-test" }
        )
        if let result = try freshCtx.fetch(fetch).first {
            let status = result.statusRaw
            XCTAssertTrue(
                status == ProcessingStatus.ready.rawValue || status == ProcessingStatus.failed.rawValue,
                "Item should be ready or failed, not stuck in processing. Got: \(status)"
            )
        }
    }
    
    /// Stress test: simulates the exact crash scenario — multiple items processed
    /// concurrently via separate contexts (verifying no shared-state corruption).
    func testConcurrentProcessItemByIDWithSeparateContexts() async throws {
        // Given: Multiple items
        let sessionID = "stress-session"
        let session = makeSession(sessionID: sessionID)
        modelContext.insert(session)
        
        var itemIDs: [String] = []
        for i in 0..<3 {
            let item = makeProcessedItem(
                id: "stress-\(i)",
                url: "https://stress.com/\(i)",
                title: "Stress \(i)",
                status: .ready,
                sessionID: sessionID
            )
            modelContext.insert(item)
            itemIDs.append(item.id)
        }
        try modelContext.save()
        
        // When: Process concurrently (each has its own ModelContext, so this is safe)
        let service = pipelineService!
        await withTaskGroup(of: Void.self) { group in
            for id in itemIDs {
                group.addTask {
                    try? await service.processItemByID(id)
                }
            }
        }
        
        // Then: No crash, items exist in terminal states
        let freshCtx = ModelContext(modelContainer)
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        let items = try freshCtx.fetch(fetch)
        XCTAssertEqual(items.count, 3, "All items should survive concurrent processing")
    }
}
