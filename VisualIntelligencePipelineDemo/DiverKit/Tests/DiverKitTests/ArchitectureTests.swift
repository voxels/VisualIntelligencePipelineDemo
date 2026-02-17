import XCTest
import SwiftData
@testable import DiverKit

@MainActor
final class ArchitectureTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var service: LocalPipelineService!

    override func setUp() async throws {
        let schema = Schema([ProcessedItem.self, SessionMetadata.self, SessionCollection.self, UserConcept.self, LocalInput.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)
        service = LocalPipelineService(modelContext: modelContext)
    }

    func testDiverObjectConformance() {
        // Given: Models of different types
        let item = ProcessedItem(id: "item-1", title: "Test Item")
        let session = SessionMetadata(sessionID: "session-1", title: "Test Session")
        let collection = SessionCollection(name: "Test Collection", sessionIDs: [])

        // Then: They should all conform to DiverObject and provide displayTitle
        XCTAssertTrue(item is any DiverObject)
        XCTAssertTrue(session is any DiverObject)
        XCTAssertTrue(collection is any DiverObject)
        
        XCTAssertEqual(item.displayTitle, "Test Item")
        XCTAssertEqual(session.displayTitle, "Test Session")
        XCTAssertEqual(collection.displayTitle, "Test Collection")
    }

    func testSessionItemRelationship() throws {
        // Given: A session and an item
        let session = SessionMetadata(sessionID: "session-1", title: "Test Session")
        let item = ProcessedItem(id: "item-1", title: "Test Item")
        modelContext.insert(session)
        modelContext.insert(item)
        
        // When: We link them
        item.session = session
        try modelContext.save()
        
        // Then: The relationship should be traversable from both sides
        XCTAssertEqual(item.session?.sessionID, "session-1")
        XCTAssertTrue(session.items?.contains(where: { $0.id == "item-1" }) ?? false)
    }

    func testCascadeDelete() throws {
        // Given: A session with an item
        let session = SessionMetadata(sessionID: "session-cascade", title: "Test Cascade")
        let item = ProcessedItem(id: "item-cascade", title: "Child Item")
        modelContext.insert(session)
        modelContext.insert(item)
        item.session = session
        try modelContext.save()
        
        // When: We delete the session
        modelContext.delete(session)
        try modelContext.save()
        
        // Then: The item should also be deleted (cascade)
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "item-cascade" })
        let items = try modelContext.fetch(fetch)
        XCTAssertTrue(items.isEmpty, "Item should have been deleted via cascade")
    }

    func testRelationshipReconciliation() async throws {
        // Given: Records with matching IDs but no pointers (simulating old data)
        let sessionID = "recon-session"
        let session = SessionMetadata(sessionID: sessionID, title: "Recon Session")
        let item = ProcessedItem(id: "recon-item", title: "Recon Item")
        item.sessionID = sessionID // Set the ID but not the pointer
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        // When: We run reconciliation
        await service.reconcileRelationships()
        
        // Then: The pointer should be established
        XCTAssertNotNil(item.session, "Relationship should be reconciled")
        XCTAssertEqual(item.session?.sessionID, sessionID)
    }
}
