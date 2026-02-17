import XCTest
import SwiftData
@testable import DiverKit

final class ProcessedItemTests: XCTestCase {

    // MARK: - ProcessingStatus Tests

    func testProcessingStatusDefaultValue() {
        let item = ProcessedItem(id: "test-id")
        XCTAssertEqual(item.status, .queued, "Default status should be .queued")
    }

    func testProcessingStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test all enum cases
        let cases: [ProcessingStatus] = [.queued, .processing, .ready, .failed, .archived]

        for status in cases {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(ProcessingStatus.self, from: data)
            XCTAssertEqual(status, decoded, "ProcessingStatus should encode/decode correctly")
        }
    }

    // MARK: - ProcessedItem Field Tests

    func testProcessedItemWithNewFields() {
        let now = Date()
        let processedAt = Date().addingTimeInterval(-3600)

        let item = ProcessedItem(
            id: "test-id",
            url: "https://example.com",
            title: "Test Item",
            status: .ready,
            source: "test-source",
            updatedAt: now,
            referenceCount: 3,
            lastProcessedAt: processedAt,
            wrappedLink: "https://secretatomics.com/w/abc123",
            payloadRef: "payload-ref-123",
            attributionID: "highlight-123"
        )

        XCTAssertEqual(item.id, "test-id")
        XCTAssertEqual(item.status, .ready)
        XCTAssertEqual(item.source, "test-source")
        XCTAssertEqual(item.updatedAt, now)
        XCTAssertEqual(item.referenceCount, 3)
        XCTAssertEqual(item.lastProcessedAt, processedAt)
        XCTAssertEqual(item.wrappedLink, "https://secretatomics.com/w/abc123")
        XCTAssertEqual(item.payloadRef, "payload-ref-123")
        XCTAssertEqual(item.attributionID, "highlight-123")
    }

    func testProcessedItemDefaultValues() {
        let item = ProcessedItem(id: "test-id")

        XCTAssertEqual(item.status, .queued)
        XCTAssertNil(item.source)
        XCTAssertEqual(item.referenceCount, 0)
        XCTAssertNil(item.lastProcessedAt)
        XCTAssertNil(item.wrappedLink)
        XCTAssertNil(item.payloadRef)
    }
    
    func testMediaInfoAbstraction() {
        let item = ProcessedItem(
            id: "media-test",
            transcription: "Hello World",
            visualTags: ["dark", "moody"],
            mediaType: "image/jpeg",
            fileSize: 1024,
            filename: "photo.jpg"
        )
        
        let info = item.mediaInfo
        
        XCTAssertEqual(info.mediaType, "image/jpeg")
        XCTAssertEqual(info.filename, "photo.jpg")
        XCTAssertEqual(info.fileSize, 1024)
        XCTAssertEqual(info.transcription, "Hello World")
        XCTAssertEqual(info.visualTags, ["dark", "moody"])
    }


    // MARK: - Payload Encoding/Decoding Tests

    func testRawPayloadEncodingDecoding() throws {
        struct TestPayload: Codable, Equatable {
            let message: String
            let count: Int
            let tags: [String]
        }

        let payload = TestPayload(
            message: "Test payload",
            count: 42,
            tags: ["tag1", "tag2", "tag3"]
        )

        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(payload)

        let item = ProcessedItem(
            id: "test-id",
            rawPayload: payloadData
        )

        XCTAssertNotNil(item.rawPayload)

        let decoder = JSONDecoder()
        let decodedPayload = try decoder.decode(TestPayload.self, from: item.rawPayload!)

        XCTAssertEqual(decodedPayload, payload)
        XCTAssertEqual(decodedPayload.message, "Test payload")
        XCTAssertEqual(decodedPayload.count, 42)
        XCTAssertEqual(decodedPayload.tags, ["tag1", "tag2", "tag3"])
    }

    func testEmptyPayload() {
        let item = ProcessedItem(id: "test-id")
        XCTAssertNil(item.rawPayload)
    }

    // MARK: - Status Transition Tests

    func testStatusTransitions() {
        let item = ProcessedItem(id: "test-id")

        // Initial state
        XCTAssertEqual(item.status, .queued)

        // Transition to processing
        item.status = .processing
        XCTAssertEqual(item.status, .processing)

        // Transition to ready
        item.status = .ready
        item.lastProcessedAt = Date()
        XCTAssertEqual(item.status, .ready)
        XCTAssertNotNil(item.lastProcessedAt)

        // Can also transition to failed
        item.status = .failed
        XCTAssertEqual(item.status, .failed)

        // Can archive
        item.status = .archived
        XCTAssertEqual(item.status, .archived)
    }

    // MARK: - Reference Count Tests

    func testReferenceCountIncrement() {
        let item = ProcessedItem(id: "test-id")
        XCTAssertEqual(item.referenceCount, 0)

        item.referenceCount += 1
        XCTAssertEqual(item.referenceCount, 1)

        item.referenceCount += 5
        XCTAssertEqual(item.referenceCount, 6)
    }
    
    // MARK: - SwiftData Round-Trip Tests
    
    @MainActor
    func testInsertFetchRoundTrip() throws {
        let manager = makeTestDataManager()
        let context = manager.mainContext
        
        let item = ProcessedItem(
            id: "roundtrip-1",
            url: "https://roundtrip.com",
            title: "Round Trip Item",
            status: .ready,
            source: "test",
            wrappedLink: "https://wrapped.com/abc",
            attributionID: "attr-123"
        )
        item.location = "New York, NY"
        item.tags = ["travel", "food"]
        item.summary = "A test summary"
        item.entityType = "web"
        
        context.insert(item)
        try context.save()
        
        // Fetch back
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "roundtrip-1" }
        )
        let fetched = try context.fetch(descriptor)
        
        XCTAssertEqual(fetched.count, 1)
        let result = fetched.first!
        XCTAssertEqual(result.url, "https://roundtrip.com")
        XCTAssertEqual(result.title, "Round Trip Item")
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.source, "test")
        XCTAssertEqual(result.wrappedLink, "https://wrapped.com/abc")
        XCTAssertEqual(result.attributionID, "attr-123")
        XCTAssertEqual(result.location, "New York, NY")
        XCTAssertEqual(result.tags, ["travel", "food"])
        XCTAssertEqual(result.summary, "A test summary")
        XCTAssertEqual(result.entityType, "web")
    }
    
    @MainActor
    func testUpdateStatusSaveAndRefetch() throws {
        let manager = makeTestDataManager()
        let context = manager.mainContext
        
        let item = ProcessedItem(id: "update-test", url: nil, title: "Before Update", status: .queued)
        context.insert(item)
        try context.save()
        
        // Update
        item.status = .processing
        item.title = "After Update"
        try context.save()
        
        // Re-fetch
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "update-test" }
        )
        let fetched = try context.fetch(descriptor)
        
        XCTAssertEqual(fetched.first?.status, .processing)
        XCTAssertEqual(fetched.first?.title, "After Update")
    }
    
    @MainActor
    func testDeleteReducesCount() throws {
        let manager = makeTestDataManager()
        let context = manager.mainContext
        
        let item1 = ProcessedItem(id: "del-1")
        let item2 = ProcessedItem(id: "del-2")
        let item3 = ProcessedItem(id: "del-3")
        context.insert(item1)
        context.insert(item2)
        context.insert(item3)
        try context.save()
        
        let allDescriptor = FetchDescriptor<ProcessedItem>()
        XCTAssertEqual(try context.fetchCount(allDescriptor), 3)
        
        context.delete(item2)
        try context.save()
        
        XCTAssertEqual(try context.fetchCount(allDescriptor), 2)
    }
    
    @MainActor
    func testSessionRelationshipPersistsThroughSave() throws {
        let manager = makeTestDataManager()
        let context = manager.mainContext
        
        let session = SessionMetadata(sessionID: "sess-1", title: "Test Session")
        let item = ProcessedItem(id: "rel-item", url: nil, title: "Item", sessionID: "sess-1")
        item.session = session
        
        context.insert(session)
        context.insert(item)
        try context.save()
        
        // Fetch item and verify relationship
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "rel-item" }
        )
        let fetched = try context.fetch(descriptor)
        
        XCTAssertEqual(fetched.first?.session?.sessionID, "sess-1")
        XCTAssertEqual(fetched.first?.sessionID, "sess-1")
    }
    
    @MainActor
    func testItemWithAllNilOptionalsSurvivesRoundTrip() throws {
        let manager = makeTestDataManager()
        let context = manager.mainContext
        
        // Item with minimal data (all optionals nil)
        let item = ProcessedItem(id: "nil-test")
        context.insert(item)
        try context.save()
        
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == "nil-test" }
        )
        let fetched = try context.fetch(descriptor)
        
        XCTAssertEqual(fetched.count, 1)
        let result = fetched.first!
        XCTAssertNil(result.url)
        XCTAssertNil(result.title)
        XCTAssertNil(result.source)
        XCTAssertNil(result.location)
        XCTAssertNil(result.summary)
        XCTAssertNil(result.wrappedLink)
        XCTAssertNil(result.rawPayload)
        XCTAssertEqual(result.status, .queued)
        XCTAssertEqual(result.referenceCount, 0)
    }
}
