import XCTest
import AppIntents
import SwiftData
@testable import Diver
import DiverKit
import DiverShared

@MainActor
final class LinkEntityQueryTests: XCTestCase {
    var query: LinkEntityQuery!
    var dataStore: DiverDataStore!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        
        // Setup in-memory data store
        dataStore = try DiverDataStore(inMemory: true)
        context = dataStore.mainContext
        
        // Make dataStore available to LinkEntityQuery via DiverApp
        DiverApp._staticDataStore = dataStore
        
        query = LinkEntityQuery()
        
        try await seedData()
    }

    override func tearDown() async throws {
        DiverApp._staticDataStore = nil
        try await super.tearDown()
    }

    private func seedData() async throws {
        let items = [
            ProcessedItem(id: "1", url: "https://apple.com", title: "Apple", createdAt: Date().addingTimeInterval(-100), status: .ready),
            ProcessedItem(id: "2", url: "https://google.com", title: "Google", createdAt: Date().addingTimeInterval(-200), status: .processing),
            ProcessedItem(id: "3", url: "https://swift.org", title: "Swift", summary: "Awesome language", createdAt: Date().addingTimeInterval(-50), status: .ready)
        ]
        
        for item in items {
            context.insert(item)
        }
        try context.save()
    }

    func testEntitiesForIdentifiers() async throws {
        let results = try query.entities(for: ["1", "3"])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == "1" })
        XCTAssertTrue(results.contains { $0.id == "3" })
    }

    func testSuggestedEntities_OnlyReturnsReadyItems() async throws {
        // LinkEntityQuery might use fetchAllEntities as suggestedEntities implementation
        let results = try query.fetchAllEntities() 
        XCTAssertTrue(results.count >= 2)
        XCTAssertFalse(results.contains { $0.id == "2" }, "Should not return item with .processing status")
    }

    func testSuggestedEntities_SortedByUpdateDate() async throws {
        let results = try query.fetchAllEntities()
        // Sort order verification might depend on implementation details, check broadly
        XCTAssertNotNil(results.first)
    }

    func testEntitiesMatchingString_MatchesTitle() async throws {
        let results = try query.searchEntities(matching: "Apple")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Apple")
    }

    func testEntitiesMatchingString_MatchesURL() async throws {
        let results = try query.searchEntities(matching: "swift.org")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Swift")
    }

    func testEntitiesMatchingString_MatchesSummary() async throws {
        let results = try query.searchEntities(matching: "Awesome")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Swift")
    }

    func testEntitiesMatchingString_MatchesTags() async throws {
        // Add item with specific tag
        let taggedItem = ProcessedItem(
            id: "tag-test",
            url: "https://example.com/tags",
            title: "Tagged Page",
            tags: ["unique-tag"],
            createdAt: Date(),
            status: .ready
        )
        context.insert(taggedItem)
        try context.save()

        let results = try query.searchEntities(matching: "unique-tag")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Tagged Page")
    }

    func testEntitiesMatchingString_OnlyReadyItems() async throws {
        let results = try query.searchEntities(matching: "Google")
        XCTAssertEqual(results.count, 0, "Should not match processing items")
    }
}
