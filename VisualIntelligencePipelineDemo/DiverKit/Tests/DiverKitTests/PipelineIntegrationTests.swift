import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

@MainActor
final class PipelineIntegrationTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
    }
    
    // MARK: - ProcessedItem Lifecycle
    
    func testCreateAndPersistProcessedItem() throws {
        let item = makeProcessedItem(
            id: "pipeline-1",
            url: "https://apple.com",
            title: "Apple",
            status: .processing,
            sessionID: "session-1",
            entityType: "web"
        )
        
        modelContext.insert(item)
        try modelContext.save()
        
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "pipeline-1" }
        )
        let fetched = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.url, "https://apple.com")
        XCTAssertEqual(fetched.first?.title, "Apple")
        XCTAssertEqual(fetched.first?.status, .processing)
        XCTAssertEqual(fetched.first?.sessionID, "session-1")
    }
    
    func testItemStatusTransitionLifecycle() throws {
        let item = makeProcessedItem(id: "lifecycle-1", status: .queued)
        modelContext.insert(item)
        try modelContext.save()
        
        // queued → processing
        item.status = .processing
        try modelContext.save()
        
        var fetched = try modelContext.fetch(FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "lifecycle-1" }))
        XCTAssertEqual(fetched.first?.status, .processing)
        
        // processing → ready
        item.status = .ready
        item.lastProcessedAt = Date()
        try modelContext.save()
        
        fetched = try modelContext.fetch(FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "lifecycle-1" }))
        XCTAssertEqual(fetched.first?.status, .ready)
        XCTAssertNotNil(fetched.first?.lastProcessedAt)
    }
    
    // MARK: - Session Assignment
    
    func testItemSessionAssignment() throws {
        let session = makeSession(sessionID: "sess-1", title: "Test Session")
        let item = makeProcessedItem(id: "sess-item-1", sessionID: "sess-1")
        item.session = session
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        // Verify bidirectional relationship
        let fetchedItem = try modelContext.fetch(
            FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "sess-item-1" })
        ).first
        
        XCTAssertEqual(fetchedItem?.sessionID, "sess-1")
        XCTAssertEqual(fetchedItem?.session?.sessionID, "sess-1")
        
        // Verify session's items
        let fetchedSession = try modelContext.fetch(
            FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == "sess-1" })
        ).first
        
        XCTAssertTrue(fetchedSession?.items?.contains(where: { $0.id == "sess-item-1" }) ?? false)
    }
    
    func testMoveItemBetweenSessions() throws {
        let session1 = makeSession(sessionID: "s1", title: "Session 1")
        let session2 = makeSession(sessionID: "s2", title: "Session 2")
        let item = makeProcessedItem(id: "movable", sessionID: "s1")
        item.session = session1
        
        modelContext.insert(session1)
        modelContext.insert(session2)
        modelContext.insert(item)
        try modelContext.save()
        
        // Move item to session 2
        item.session = session2
        item.sessionID = "s2"
        try modelContext.save()
        
        let fetchedItem = try modelContext.fetch(
            FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "movable" })
        ).first
        
        XCTAssertEqual(fetchedItem?.sessionID, "s2")
        XCTAssertEqual(fetchedItem?.session?.sessionID, "s2")
    }
    
    // MARK: - Queue Store Integration
    
    func testQueueStoreEnqueueAndDequeue() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try DiverQueueStore(directoryURL: tempDir)
        
        // Enqueue
        let descriptor = makeDescriptor(id: "q1", url: "https://test.com", title: "Queued Item")
        let queueItem = DiverQueueItem(action: "save", descriptor: descriptor)
        try store.enqueue(queueItem)
        
        // Pending
        let pending = try store.pendingEntries()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.item.descriptor.id, "q1")
        XCTAssertEqual(pending.first?.item.descriptor.title, "Queued Item")
        
        // Complete (remove)
        try store.remove(pending.first!)
        
        let remaining = try store.pendingEntries()
        XCTAssertTrue(remaining.isEmpty)
    }
    
    func testQueueStoreMultipleItemsProcessedInOrder() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try DiverQueueStore(directoryURL: tempDir)
        
        // Enqueue 5 items with slightly different timestamps
        for i in 0..<5 {
            let desc = makeDescriptor(
                id: "order-\(i)",
                url: "https://order-\(i).com",
                title: "Item \(i)"
            )
            let item = DiverQueueItem(
                action: "save",
                descriptor: desc,
                createdAt: Date().addingTimeInterval(Double(i))
            )
            try store.enqueue(item)
        }
        
        let pending = try store.pendingEntries()
        XCTAssertEqual(pending.count, 5)
        
        // Verify order (should be sorted by createdAt)
        for i in 0..<5 {
            XCTAssertEqual(pending[i].item.descriptor.id, "order-\(i)")
        }
    }
    
    func testQueueStoreRemoveAll() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try DiverQueueStore(directoryURL: tempDir)
        
        for i in 0..<3 {
            let desc = makeDescriptor(id: "rm-\(i)", url: "https://rm.com/\(i)", title: "RM \(i)")
            try store.enqueue(DiverQueueItem(action: "save", descriptor: desc))
        }
        
        XCTAssertEqual(try store.pendingEntries().count, 3)
        
        try store.removeAll()
        
        XCTAssertEqual(try store.pendingEntries().count, 0)
    }
    
    // MARK: - Duplicate ID Handling
    
    func testDuplicateItemIDUpdatesExisting() throws {
        let item1 = makeProcessedItem(id: "dup-1", title: "First", status: .ready)
        modelContext.insert(item1)
        try modelContext.save()
        
        // Fetch and update (simulating reprocess)
        let fetchDesc = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "dup-1" }
        )
        if let existing = try modelContext.fetch(fetchDesc).first {
            existing.title = "Updated"
            existing.status = .processing
            try modelContext.save()
        }
        
        // Verify only one item exists
        let allItems = try modelContext.fetch(FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "dup-1" }
        ))
        XCTAssertEqual(allItems.count, 1)
        XCTAssertEqual(allItems.first?.title, "Updated")
    }
    
    // MARK: - Edge Cases
    
    func testItemWithEmptyURL() throws {
        let item = makeProcessedItem(id: "empty-url", url: "", title: "No URL")
        modelContext.insert(item)
        try modelContext.save()
        
        let fetched = try modelContext.fetch(
            FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "empty-url" })
        )
        XCTAssertEqual(fetched.first?.url, "")
    }
    
    func testItemWithAttribution() throws {
        let item = ProcessedItem(
            id: "attr-1",
            url: "https://shared.com",
            title: "Shared Link",
            attributionID: "contact-123"
        )
        modelContext.insert(item)
        try modelContext.save()
        
        let fetched = try modelContext.fetch(
            FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "attr-1" })
        )
        XCTAssertEqual(fetched.first?.attributionID, "contact-123")
    }
    
    func testBulkInsertAndQuery() throws {
        // Insert 50 items across 5 sessions
        for s in 0..<5 {
            let session = makeSession(sessionID: "bulk-s\(s)", title: "Session \(s)")
            modelContext.insert(session)
            
            for i in 0..<10 {
                let item = makeProcessedItem(
                    id: "bulk-\(s)-\(i)",
                    title: "Item \(s)-\(i)",
                    status: i % 3 == 0 ? .processing : .ready,
                    sessionID: "bulk-s\(s)"
                )
                item.session = session
                modelContext.insert(item)
            }
        }
        try modelContext.save()
        
        // Query: all ready items
        let readyDesc = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.status == .ready }
        )
        let readyItems = try modelContext.fetch(readyDesc)
        
        // 10 items per session, 4 out of 10 have i%3==0 (processing), so 6-7 per session are ready
        XCTAssertGreaterThan(readyItems.count, 25)
        XCTAssertLessThan(readyItems.count, 50)
        
        // Query: items in specific session
        let sessionDesc = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == "bulk-s0" }
        )
        let sessionItems = try modelContext.fetch(sessionDesc)
        XCTAssertEqual(sessionItems.count, 10)
    }
    
    func testDeleteItemFromSession() throws {
        let session = makeSession(sessionID: "del-sess", title: "Delete Test")
        let item1 = makeProcessedItem(id: "del-i1", sessionID: "del-sess")
        let item2 = makeProcessedItem(id: "del-i2", sessionID: "del-sess")
        item1.session = session
        item2.session = session
        
        modelContext.insert(session)
        modelContext.insert(item1)
        modelContext.insert(item2)
        try modelContext.save()
        
        // Delete one item
        modelContext.delete(item1)
        try modelContext.save()
        
        // Session should still exist with one item
        let sessionFetch = try modelContext.fetch(
            FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == "del-sess" })
        )
        XCTAssertEqual(sessionFetch.count, 1)
        
        let remainingItems = try modelContext.fetch(
            FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == "del-sess" })
        )
        XCTAssertEqual(remainingItems.count, 1)
        XCTAssertEqual(remainingItems.first?.id, "del-i2")
    }
    
    func testQueueStoreEmptyDirectory() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try DiverQueueStore(directoryURL: tempDir)
        let pending = try store.pendingEntries()
        
        XCTAssertTrue(pending.isEmpty, "New queue should have no pending entries")
    }
}
