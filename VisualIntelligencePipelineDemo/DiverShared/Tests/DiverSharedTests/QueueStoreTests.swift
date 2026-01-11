import XCTest
@testable import DiverShared

final class QueueStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testEnqueueCreatesFileAndReturnsRecord() throws {
        let queue = try DiverQueueStore(directoryURL: tempDirectory)
        let descriptor = DiverItemDescriptor(
            id: "id",
            url: "https://example.com",
            title: "Example"
        )
        let item = DiverQueueItem(action: "save", descriptor: descriptor, source: "extension")

        let record = try queue.enqueue(item)

        XCTAssertTrue(FileManager.default.fileExists(atPath: record.fileURL.path))
        XCTAssertEqual(record.item.action, "save")
        XCTAssertEqual(record.item.source, "extension")
    }

    func testPendingEntriesSortedByCreationDate() throws {
        let queue = try DiverQueueStore(directoryURL: tempDirectory)
        let descriptor = DiverItemDescriptor(
            id: "id",
            url: "https://example.com",
            title: "Example"
        )

        let older = DiverQueueItem(
            action: "save",
            descriptor: descriptor,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newer = DiverQueueItem(
            action: "save",
            descriptor: descriptor,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        _ = try queue.enqueue(newer)
        _ = try queue.enqueue(older)

        let entries = try queue.pendingEntries()
        XCTAssertEqual(entries.map(\.item.createdAt), [older.createdAt, newer.createdAt])
    }

    func testRemoveDeletesRecord() throws {
        let queue = try DiverQueueStore(directoryURL: tempDirectory)
        let descriptor = DiverItemDescriptor(
            id: "id",
            url: "https://example.com",
            title: "Example"
        )
        let record = try queue.enqueue(DiverQueueItem(action: "save", descriptor: descriptor))

        try queue.remove(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: record.fileURL.path))
        XCTAssertTrue(try queue.pendingEntries().isEmpty)
    }
}
