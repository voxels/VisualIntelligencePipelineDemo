import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

@MainActor
final class SidebarViewModelTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var viewModel: SidebarViewModel!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
        viewModel = SidebarViewModel()
    }
    
    // MARK: - Session CRUD
    
    func testDeleteSessionRemovesFromContext() throws {
        let session = makeSession(sessionID: "s1", title: "Delete Me")
        modelContext.insert(session)
        try modelContext.save()
        
        viewModel.deleteSession(session, context: modelContext)
        
        let descriptor = FetchDescriptor<SessionMetadata>()
        let sessions = try modelContext.fetch(descriptor)
        XCTAssertTrue(sessions.isEmpty, "Session should be deleted")
    }
    
    func testDeleteSessionSetsPerformingAction() throws {
        let session = makeSession()
        modelContext.insert(session)
        try modelContext.save()
        
        // After deleteSession completes, isPerformingAction should be false (it's synchronous)
        viewModel.deleteSession(session, context: modelContext)
        XCTAssertFalse(viewModel.isPerformingAction, "Should be false after sync operation completes")
    }
    
    func testRenameSessionUpdatesTitle() throws {
        let session = makeSession(sessionID: "s1", title: "Old Name")
        modelContext.insert(session)
        try modelContext.save()
        
        let beforeDate = session.updatedAt
        viewModel.renameSession(session, title: "New Name", context: modelContext)
        
        XCTAssertEqual(session.title, "New Name")
        XCTAssertGreaterThanOrEqual(session.updatedAt ?? .distantPast, beforeDate ?? .distantPast,
                                    "updatedAt should be bumped")
    }
    
    func testRenameSessionWithEmptyString() throws {
        let session = makeSession(sessionID: "s1", title: "Has a Name")
        modelContext.insert(session)
        try modelContext.save()
        
        viewModel.renameSession(session, title: "", context: modelContext)
        
        XCTAssertEqual(session.title, "", "Should allow empty string (UI should validate, not the VM)")
    }
    
    func testToggleFavorite() throws {
        let session = makeSession()
        modelContext.insert(session)
        try modelContext.save()
        
        XCTAssertFalse(session.isFavorite, "Default should be false")
        
        viewModel.toggleFavorite(for: session, context: modelContext)
        XCTAssertTrue(session.isFavorite)
        
        viewModel.toggleFavorite(for: session, context: modelContext)
        XCTAssertFalse(session.isFavorite, "Second toggle should revert")
    }
    
    // MARK: - Collection Management
    
    func testCreateCollectionWithSession() throws {
        let session = makeSession(sessionID: "s1", title: "My Session")
        modelContext.insert(session)
        try modelContext.save()
        
        viewModel.createCollection(name: "My Collection", session: session, context: modelContext)
        
        let descriptor = FetchDescriptor<SessionCollection>()
        let collections = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections.first?.name, "My Collection")
        XCTAssertTrue(collections.first?.sessionIDs.contains("s1") ?? false)
    }
    
    func testAddSessionToCollectionPreventsDoubleAdd() throws {
        let collection = makeCollection(collectionID: "c1", name: "Test", sessionIDs: ["s1"])
        let session = makeSession(sessionID: "s1", title: "Already Here")
        modelContext.insert(collection)
        modelContext.insert(session)
        try modelContext.save()
        
        // Try to add the same session again
        viewModel.addSessionToCollection(session, collection: collection, context: modelContext)
        
        // Should NOT have duplicates
        let count = collection.sessionIDs.filter { $0 == "s1" }.count
        XCTAssertEqual(count, 1, "Should not add duplicate session to collection")
    }
    
    func testRenameCollectionUpdatesName() throws {
        let collection = makeCollection(collectionID: "c1", name: "Old Name")
        modelContext.insert(collection)
        try modelContext.save()
        
        viewModel.renameCollection(collection, name: "New Name", context: modelContext)
        
        XCTAssertEqual(collection.name, "New Name")
    }
    
    // MARK: - Sort & Filter
    
    func testSortAndFilterWithEmptySearchReturnsAll() {
        viewModel.searchText = ""
        let items = (1...3).map { i in
            makeProcessedItem(id: "item-\(i)", title: "Item \(i)")
        }
        
        let result = viewModel.sortAndFilter(items: items)
        XCTAssertEqual(result.count, 3, "Empty search should return all items")
    }
    
    func testSortAndFilterByTitle() {
        viewModel.searchText = "Apple"
        let items = [
            makeProcessedItem(id: "1", title: "Apple Pie"),
            makeProcessedItem(id: "2", title: "Banana Bread"),
            makeProcessedItem(id: "3", title: "Apple Sauce")
        ]
        
        let result = viewModel.sortAndFilter(items: items)
        XCTAssertEqual(result.count, 2, "Should match 2 items with 'Apple' in title")
    }
    
    func testSortAndFilterCaseInsensitive() {
        viewModel.searchText = "apple"
        let items = [
            makeProcessedItem(id: "1", title: "APPLE"),
            makeProcessedItem(id: "2", title: "Apple"),
            makeProcessedItem(id: "3", title: "Banana")
        ]
        
        let result = viewModel.sortAndFilter(items: items)
        XCTAssertEqual(result.count, 2, "Search should be case-insensitive")
    }
    
    func testSortAndFilterDeduplicates() {
        viewModel.searchText = ""
        let item = makeProcessedItem(id: "duplicate", title: "Same Item")
        // Same item appears twice in input
        let result = viewModel.sortAndFilter(items: [item, item])
        XCTAssertEqual(result.count, 1, "Should deduplicate items with same ID")
    }
    
    func testSortAndFilterProcessingItemsFirst() {
        viewModel.searchText = ""
        let items = [
            makeProcessedItem(id: "1", title: "Ready", status: .ready),
            makeProcessedItem(id: "2", title: "Processing", status: .processing),
            makeProcessedItem(id: "3", title: "Queued", status: .queued)
        ]
        
        let result = viewModel.sortAndFilter(items: items)
        XCTAssertEqual(result.first?.title, "Processing", "Processing items should sort first")
    }
    
    func testSortAndFilterByURL() {
        viewModel.searchText = "github"
        let items = [
            makeProcessedItem(id: "1", url: "https://github.com/repo", title: "Repo"),
            makeProcessedItem(id: "2", url: "https://docs.example.com", title: "Docs"),
        ]
        
        let result = viewModel.sortAndFilter(items: items)
        XCTAssertEqual(result.count, 1, "Should match URL containing 'github'")
        XCTAssertEqual(result.first?.id, "1")
    }
    
    func testSortAndFilterByTags() {
        viewModel.searchText = "photography"
        let item1 = makeProcessedItem(id: "1", title: "Sunset", tags: ["photography", "nature"])
        let item2 = makeProcessedItem(id: "2", title: "Code", tags: ["programming"])
        
        let result = viewModel.sortAndFilter(items: [item1, item2])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }
    
    func testSortAndFilterWithNoMatches() {
        viewModel.searchText = "zzzznonexistent"
        let items = [
            makeProcessedItem(id: "1", title: "Apple"),
            makeProcessedItem(id: "2", title: "Banana")
        ]
        
        let result = viewModel.sortAndFilter(items: items)
        XCTAssertTrue(result.isEmpty, "Non-matching search should return empty")
    }
    
    // MARK: - Empty Sessions Cleanup
    
    func testRemoveEmptySessionsDeletesOrphans() throws {
        // Session with no items
        let emptySession = makeSession(sessionID: "empty", title: "Empty")
        // Session with an item
        let fullSession = makeSession(sessionID: "full", title: "Full")
        let item = makeProcessedItem(id: "i1", sessionID: "full")
        item.session = fullSession
        
        modelContext.insert(emptySession)
        modelContext.insert(fullSession)
        modelContext.insert(item)
        try modelContext.save()
        
        viewModel.removeEmptySessions(context: modelContext)
        
        let descriptor = FetchDescriptor<SessionMetadata>()
        let sessions = try modelContext.fetch(descriptor)
        
        // Only the session with items should remain
        XCTAssertEqual(sessions.count, 1, "Should only keep sessions that have items")
        XCTAssertEqual(sessions.first?.sessionID, "full")
    }
    
    // MARK: - Drag & Drop (from existing tests, enhanced)
    
    func testMoveItemToNonexistentSession() throws {
        let session = makeSession(sessionID: "s1", title: "Source")
        let item = makeProcessedItem(id: "i1", sessionID: "s1")
        item.session = session
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        // Try to move to a session that doesn't exist
        viewModel.moveItem(itemID: "i1", toSessionID: "nonexistent", context: modelContext)
        
        // Item should remain in its original session (graceful failure)
        XCTAssertEqual(item.sessionID, "s1", "Item should stay in original session when target doesn't exist")
    }
    
    func testCreateSessionWithItemInCollection() throws {
        let collection = makeCollection(collectionID: "c1", name: "Test Collection")
        let item = makeProcessedItem(id: "i1", title: "New Item")
        
        modelContext.insert(collection)
        modelContext.insert(item)
        try modelContext.save()
        
        let newSession = viewModel.createSessionWithItem(item, in: collection, context: modelContext)
        
        XCTAssertEqual(item.sessionID, newSession.sessionID)
        XCTAssertEqual(item.session?.sessionID, newSession.sessionID)
        XCTAssertTrue(collection.sessionIDs.contains(newSession.sessionID))
        XCTAssertEqual(newSession.collectionID, "c1")
    }
}
