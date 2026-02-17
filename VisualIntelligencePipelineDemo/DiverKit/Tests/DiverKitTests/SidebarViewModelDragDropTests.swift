import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

@MainActor
final class SidebarViewModelDragDropTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var viewModel: SidebarViewModel!

    override func setUp() async throws {
        let unifiedDataManager = UnifiedDataManager(inMemory: true)
        modelContainer = unifiedDataManager.container
        modelContext = unifiedDataManager.mainContext
        viewModel = SidebarViewModel()
    }

    func testMoveItemBetweenSessions() async throws {
        // Given: Two sessions and an item in the first session
        let session1 = SessionMetadata(sessionID: "s1", title: "Session 1")
        let session2 = SessionMetadata(sessionID: "s2", title: "Session 2")
        let item = ProcessedItem(id: "i1", url: nil, title: "Item 1", sessionID: "s1")
        item.session = session1
        
        modelContext.insert(session1)
        modelContext.insert(session2)
        modelContext.insert(item)
        try modelContext.save()
        
        // When: We move the item to the second session
        viewModel.moveItem(itemID: "i1", toSessionID: "s2", context: modelContext)
        
        // Then: The item's sessionID and relationship should be updated
        XCTAssertEqual(item.sessionID, "s2")
        XCTAssertEqual(item.session?.sessionID, "s2")
    }

    func testMoveSessionToCollection() async throws {
        // Given: A collection and a standalone session
        let collection = SessionCollection(collectionID: "c1", name: "Collection 1")
        let session = SessionMetadata(sessionID: "s1", title: "Session 1")
        
        modelContext.insert(collection)
        modelContext.insert(session)
        try modelContext.save()
        
        // When: We move the session to the collection
        viewModel.moveSessionToCollection(sessionID: "s1", collectionID: "c1", context: modelContext)
        
        // Then: The session's collectionID and parentCollection relationship should be updated
        XCTAssertEqual(session.collectionID, "c1")
        XCTAssertEqual(session.parentCollection?.collectionID, "c1")
        
        // And: The collection's sessionIDs array should include the sessionID
        XCTAssertTrue(collection.sessionIDs.contains("s1"))
    }
}

extension SidebarViewModelDragDropTests {
    func testMoveItemsBatchUpdatesSessionID() async throws {
        // Given: Two sessions and an item in the first session
        let session1 = SessionMetadata(sessionID: "s1", title: "Session 1")
        let session2 = SessionMetadata(sessionID: "s2", title: "Session 2")
        let item = ProcessedItem(id: "i1", url: nil, title: "Item 1", sessionID: "s1")
        item.session = session1
        
        modelContext.insert(session1)
        modelContext.insert(session2)
        modelContext.insert(item)
        try modelContext.save()
        
        // When: We use the batch moveItems handler (used by drag-drop)
        let transfers = [ItemTransfer(id: "i1")]
        viewModel.moveItems(transfers, to: session2, context: modelContext)
        
        // Then: BOTH sessionID (string) and session (relationship) should be updated
        XCTAssertEqual(item.sessionID, "s2", "sessionID string must be updated")
        XCTAssertEqual(item.session?.sessionID, "s2", "session relationship must be updated")
    }
}
