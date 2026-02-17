import XCTest
import SwiftData
import CoreLocation
import DiverShared
@testable import DiverKit

/// Tests for LocalPipelineService library maintenance sub-methods.
/// Each method is tested independently using in-memory SwiftData.
@MainActor
final class LibraryMaintenanceTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var service: LocalPipelineService!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
        service = LocalPipelineService(modelContext: modelContext)
    }
    
    // MARK: - recoverStuckItems
    
    func testRecoverStuckItems_ResetsProcessingToQueued() throws {
        // Insert items stuck in processing
        let stuck1 = makeProcessedItem(id: "stuck-1", title: "Stuck A", status: .processing)
        let stuck2 = makeProcessedItem(id: "stuck-2", title: "Stuck B", status: .processing)
        let ready = makeProcessedItem(id: "ready-1", title: "Ready", status: .ready)
        
        modelContext.insert(stuck1)
        modelContext.insert(stuck2)
        modelContext.insert(ready)
        try modelContext.save()
        
        // Recover
        try service.recoverStuckItems()
        
        // Verify stuck items reset to queued
        let fetchStuck = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "queued" }
        )
        let recovered = try modelContext.fetch(fetchStuck)
        XCTAssertEqual(recovered.count, 2, "Both stuck items should be reset to queued")
        
        // Verify ready items untouched
        let fetchReady = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "ready" }
        )
        let readyItems = try modelContext.fetch(fetchReady)
        XCTAssertEqual(readyItems.count, 1)
    }
    
    func testRecoverStuckItems_CreatesLocalInput() throws {
        let stuck = makeProcessedItem(id: "stuck-input", title: "Stuck", status: .processing)
        stuck.url = "https://stuck.com"
        stuck.sessionID = "sess-stuck"
        modelContext.insert(stuck)
        try modelContext.save()
        
        try service.recoverStuckItems()
        
        // Verify a LocalInput was created for re-processing
        let inputFetch = FetchDescriptor<LocalInput>()
        let inputs = try modelContext.fetch(inputFetch)
        XCTAssertEqual(inputs.count, 1, "A LocalInput should be created for the stuck item")
        XCTAssertEqual(inputs.first?.url, "https://stuck.com")
        XCTAssertEqual(inputs.first?.sessionID, "sess-stuck")
    }
    
    func testRecoverStuckItems_NoStuckItems() throws {
        let item = makeProcessedItem(id: "ready-only", status: .ready)
        modelContext.insert(item)
        try modelContext.save()
        
        // Should not throw or modify anything
        try service.recoverStuckItems()
        
        let fetch = FetchDescriptor<ProcessedItem>()
        let items = try modelContext.fetch(fetch)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.status, .ready)
    }
    
    // MARK: - assignOrphanedItems
    
    func testAssignOrphanedItems_MatchesByTime() throws {
        // Session created at T
        let sessionTime = Date()
        let session = makeSession(sessionID: "s-time", title: "Time Session", createdAt: sessionTime)
        modelContext.insert(session)
        
        // Orphan created 2 minutes after session (within 5-min no-location window)
        let orphan = makeProcessedItem(
            id: "orphan-1",
            title: "Orphan",
            status: .ready,
            createdAt: sessionTime.addingTimeInterval(120)
        )
        // sessionID is nil = orphan
        orphan.sessionID = nil
        modelContext.insert(orphan)
        try modelContext.save()
        
        try service.assignOrphanedItems()
        
        // Verify orphan was assigned
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "orphan-1" })
        let result = try modelContext.fetch(fetch)
        XCTAssertEqual(result.first?.sessionID, "s-time", "Orphan should be assigned to nearest session")
    }
    
    func testAssignOrphanedItems_CreatesNewSessionWhenNoMatch() throws {
        // Session created far in the past
        let session = makeSession(sessionID: "old-sess", title: "Old", createdAt: Date().addingTimeInterval(-86400))
        modelContext.insert(session)
        
        // Orphan created now (far from any session)
        let orphan = makeProcessedItem(id: "orphan-new", title: "New Orphan", status: .ready)
        orphan.sessionID = nil
        modelContext.insert(orphan)
        try modelContext.save()
        
        try service.assignOrphanedItems()
        
        // A new session should have been created
        let sessionFetch = FetchDescriptor<SessionMetadata>()
        let sessions = try modelContext.fetch(sessionFetch)
        XCTAssertEqual(sessions.count, 2, "A new session should be created for the unmatched orphan")
        
        // Orphan should now have a sessionID
        let itemFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "orphan-new" })
        let item = try modelContext.fetch(itemFetch).first
        XCTAssertNotNil(item?.sessionID)
    }
    
    func testAssignOrphanedItems_NoOrphans() throws {
        let session = makeSession(sessionID: "sess-ok", title: "OK")
        let item = makeProcessedItem(id: "has-session", sessionID: "sess-ok")
        item.session = session
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        // Should complete without error
        try service.assignOrphanedItems()
        
        // Nothing changes
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "has-session" })
        XCTAssertEqual(try modelContext.fetch(fetch).first?.sessionID, "sess-ok")
    }
    
    // MARK: - regenerateMissingSessions
    
    func testRegenerateMissingSessions_CreatesForOrphanedSessionID() throws {
        // Item with a sessionID but no matching SessionMetadata
        let item = makeProcessedItem(id: "no-session-item", title: "Orphan", sessionID: "missing-sess-id")
        modelContext.insert(item)
        try modelContext.save()
        
        // Verify no session exists
        let beforeFetch = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate { $0.sessionID == "missing-sess-id" }
        )
        XCTAssertEqual(try modelContext.fetch(beforeFetch).count, 0)
        
        try service.regenerateMissingSessions()
        
        // Session should now exist
        let afterFetch = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate { $0.sessionID == "missing-sess-id" }
        )
        let sessions = try modelContext.fetch(afterFetch)
        XCTAssertEqual(sessions.count, 1, "Missing session should be regenerated")
        XCTAssertEqual(sessions.first?.createdAt, item.createdAt, "Session should use item's creation date")
    }
    
    func testRegenerateMissingSessions_SkipsExistingSessions() throws {
        let session = makeSession(sessionID: "exists-sess", title: "Existing")
        let item = makeProcessedItem(id: "has-session-item", sessionID: "exists-sess")
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        try service.regenerateMissingSessions()
        
        // No duplicate session created
        let fetch = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate { $0.sessionID == "exists-sess" }
        )
        XCTAssertEqual(try modelContext.fetch(fetch).count, 1)
    }
    
    // MARK: - consolidateSessions
    
    func testConsolidateSessions_MergesFragmented() throws {
        let now = Date()
        
        // Two sessions with same time (< 5s) and same location (< 50m)
        let session1 = makeSession(
            sessionID: "frag-1",
            title: "Fragment 1",
            createdAt: now,
            latitude: 40.7128,
            longitude: -74.0060
        )
        let session2 = makeSession(
            sessionID: "frag-2",
            title: "Fragment 2",
            createdAt: now.addingTimeInterval(2), // 2s later
            latitude: 40.7128,
            longitude: -74.0060 // Same location
        )
        
        let item1 = makeProcessedItem(id: "frag-item-1", sessionID: "frag-1")
        let item2 = makeProcessedItem(id: "frag-item-2", sessionID: "frag-2")
        
        modelContext.insert(session1)
        modelContext.insert(session2)
        modelContext.insert(item1)
        modelContext.insert(item2)
        try modelContext.save()
        
        try service.consolidateSessions()
        
        // Items should now share the same sessionID
        let allItems = try modelContext.fetch(FetchDescriptor<ProcessedItem>())
        let sessionIDs = Set(allItems.compactMap(\.sessionID))
        XCTAssertEqual(sessionIDs.count, 1, "Fragmented sessions should be consolidated into one")
    }
    
    func testConsolidateSessions_KeepsSeparateWhenFarApart() throws {
        let now = Date()
        
        // Two sessions far apart in time
        let session1 = makeSession(
            sessionID: "sep-1",
            title: "Session 1",
            createdAt: now,
            latitude: 40.7128,
            longitude: -74.0060
        )
        let session2 = makeSession(
            sessionID: "sep-2",
            title: "Session 2",
            createdAt: now.addingTimeInterval(3600), // 1 hour later
            latitude: 34.0522,
            longitude: -118.2437 // Different city
        )
        
        modelContext.insert(session1)
        modelContext.insert(session2)
        try modelContext.save()
        
        try service.consolidateSessions()
        
        // Both sessions should remain
        let sessions = try modelContext.fetch(FetchDescriptor<SessionMetadata>())
        XCTAssertEqual(sessions.count, 2, "Separate sessions should not be consolidated")
    }
    
    // MARK: - reconcileRelationships
    
    func testReconcileRelationships_LinksItemToSession() async throws {
        let session = makeSession(sessionID: "recon-sess", title: "Recon Session")
        let item = makeProcessedItem(id: "recon-item", sessionID: "recon-sess")
        // Don't set item.session — that's what reconcile fixes
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        XCTAssertNil(item.session, "Item should start without session relationship")
        
        await service.reconcileRelationships()
        
        // Re-fetch to see updated relationship
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "recon-item" })
        let result = try modelContext.fetch(fetch).first
        XCTAssertEqual(result?.session?.sessionID, "recon-sess", "Relationship should be reconciled")
    }
    
    func testReconcileRelationships_LinksSessionToCollection() async throws {
        let collection = makeCollection(collectionID: "recon-coll", name: "Recon Collection")
        let session = makeSession(sessionID: "recon-sess-coll", title: "Session")
        session.collectionID = "recon-coll"
        // Don't set session.parentCollection — that's what reconcile fixes
        
        modelContext.insert(collection)
        modelContext.insert(session)
        try modelContext.save()
        
        XCTAssertNil(session.parentCollection, "Session should start without collection relationship")
        
        await service.reconcileRelationships()
        
        let fetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == "recon-sess-coll" })
        let result = try modelContext.fetch(fetch).first
        XCTAssertEqual(result?.parentCollection?.collectionID, "recon-coll", "Session-collection relationship should be reconciled")
    }
}
