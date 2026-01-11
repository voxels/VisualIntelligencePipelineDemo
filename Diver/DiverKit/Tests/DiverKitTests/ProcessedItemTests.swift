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
            themes: ["dark", "moody"],
            mediaType: "image/jpeg",
            fileSize: 1024,
            filename: "photo.jpg"
        )
        
        let info = item.mediaInfo
        
        XCTAssertEqual(info.mediaType, "image/jpeg")
        XCTAssertEqual(info.filename, "photo.jpg")
        XCTAssertEqual(info.fileSize, 1024)
        XCTAssertEqual(info.transcription, "Hello World")
        XCTAssertEqual(info.themes, ["dark", "moody"])
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
}
