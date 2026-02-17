import XCTest
import SwiftData
@testable import DiverKit

@MainActor
final class DiverCollectionTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
    }
    
    // MARK: - Creation & Persistence
    
    func testCreateCollectionPersists() throws {
        let collection = makeCollection(name: "My Collection")
        modelContext.insert(collection)
        try modelContext.save()
        
        let descriptor = FetchDescriptor<SessionCollection>()
        let fetched = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "My Collection")
    }
    
    func testCollectionDefaultValues() {
        let collection = SessionCollection(collectionID: "c1", name: "Test")
        
        XCTAssertEqual(collection.collectionID, "c1")
        XCTAssertEqual(collection.name, "Test")
        XCTAssertTrue(collection.sessionIDs.isEmpty)
    }
    
    // MARK: - Session Relationships
    
    func testAddSessionToCollectionUpdatesRelationships() throws {
        let collection = makeCollection(collectionID: "c1", name: "Travel")
        let session = makeSession(sessionID: "s1", title: "Tokyo Trip")
        
        modelContext.insert(collection)
        modelContext.insert(session)
        
        // Add session to collection
        collection.sessionIDs.append("s1")
        session.collectionID = "c1"
        session.parentCollection = collection
        
        try modelContext.save()
        
        XCTAssertTrue(collection.sessionIDs.contains("s1"))
        XCTAssertEqual(session.collectionID, "c1")
        XCTAssertEqual(session.parentCollection?.collectionID, "c1")
    }
    
    func testRemoveSessionFromCollectionCleansRelationships() throws {
        let collection = makeCollection(collectionID: "c1", name: "Work", sessionIDs: ["s1"])
        let session = makeSession(sessionID: "s1", title: "Meeting Notes")
        session.collectionID = "c1"
        session.parentCollection = collection
        
        modelContext.insert(collection)
        modelContext.insert(session)
        try modelContext.save()
        
        // Remove session from collection
        collection.sessionIDs.removeAll { $0 == "s1" }
        session.collectionID = nil
        session.parentCollection = nil
        
        try modelContext.save()
        
        XCTAssertFalse(collection.sessionIDs.contains("s1"))
        XCTAssertNil(session.collectionID)
        XCTAssertNil(session.parentCollection)
    }
    
    func testDeleteCollectionOrphansSessionsDoesNotDeleteThem() throws {
        let collection = makeCollection(collectionID: "c1", name: "Archive", sessionIDs: ["s1", "s2"])
        let session1 = makeSession(sessionID: "s1", title: "Session 1")
        let session2 = makeSession(sessionID: "s2", title: "Session 2")
        session1.collectionID = "c1"
        session1.parentCollection = collection
        session2.collectionID = "c1"
        session2.parentCollection = collection
        
        modelContext.insert(collection)
        modelContext.insert(session1)
        modelContext.insert(session2)
        try modelContext.save()
        
        // Delete the collection
        modelContext.delete(collection)
        try modelContext.save()
        
        // Sessions should still exist
        let sessionDescriptor = FetchDescriptor<SessionMetadata>()
        let sessions = try modelContext.fetch(sessionDescriptor)
        XCTAssertEqual(sessions.count, 2, "Deleting collection should NOT delete sessions")
        
        // Collections should be empty
        let collectionDescriptor = FetchDescriptor<SessionCollection>()
        let collections = try modelContext.fetch(collectionDescriptor)
        XCTAssertTrue(collections.isEmpty)
    }
    
    func testMultipleSessionsInCollection() throws {
        let collection = makeCollection(collectionID: "c1", name: "Research")
        
        let sessions = (1...5).map { i in
            makeSession(sessionID: "s\(i)", title: "Session \(i)")
        }
        
        modelContext.insert(collection)
        for session in sessions {
            modelContext.insert(session)
            collection.sessionIDs.append(session.sessionID)
            session.collectionID = "c1"
            session.parentCollection = collection
        }
        try modelContext.save()
        
        XCTAssertEqual(collection.sessionIDs.count, 5)
    }
    
    // MARK: - SwiftData Round-Trip
    
    func testCollectionSurvivesRoundTrip() throws {
        let id = "roundtrip-test"
        let collection = makeCollection(collectionID: id, name: "Round Trip", sessionIDs: ["s1", "s2"])
        modelContext.insert(collection)
        try modelContext.save()
        
        // Fetch back
        let descriptor = FetchDescriptor<SessionCollection>(
            predicate: #Predicate { $0.collectionID == id }
        )
        let fetched = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Round Trip")
        XCTAssertEqual(fetched.first?.sessionIDs, ["s1", "s2"])
    }
}
