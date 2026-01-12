import XCTest
@testable import DiverShared

final class MessagesLaunchStoreTests: XCTestCase {

    var testConfig: AppGroupConfig!

    override func setUp() {
        super.setUp()
        // Create test config pointing to a temporary directory if possible, 
        // but for now we'll use the default and just clean up.
        // In a real test we'd mock AppGroupContainer to return a temp URL.
        testConfig = .default
        
        // Ensure clean state
        if let url = fileURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    override func tearDown() {
        if let url = fileURL() {
            try? FileManager.default.removeItem(at: url)
        }
        testConfig = nil
        super.tearDown()
    }

    private func fileURL() -> URL? {
        guard let baseURL = try? AppGroupContainer.containerURL(config: testConfig) else { return nil }
        return baseURL.appendingPathComponent("messages_launch_request.json")
    }

    // MARK: - Save Tests

    func testSaveStoresMessageLaunchRequest() {
        let testBody = "https://secretatomics.com/w/abc123"

        MessagesLaunchStore.save(body: testBody, config: testConfig)

        // Verify it was stored
        guard let url = fileURL() else {
            XCTFail("Could not get file URL")
            return
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Should store file in container")

        // Verify it can be decoded
        let storedData = try? Data(contentsOf: url)
        XCTAssertNotNil(storedData)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try? decoder.decode(MessagesLaunchRequest.self, from: storedData!)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.body, testBody)
    }

    func testSaveTrimsLongBody() {
        let longBody = String(repeating: "a", count: 3000)

        MessagesLaunchStore.save(body: longBody, config: testConfig)

        let consumed = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.body?.count, 2000, "Should trim to 2000 characters")
    }

    func testSaveWithNilBody() {
        MessagesLaunchStore.save(body: nil, config: testConfig)

        let consumed = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertNotNil(consumed, "Should store request even with nil body")
        XCTAssertNil(consumed?.body)
    }

    // MARK: - Consume Tests

    func testConsumeRetrievesAndRemovesRequest() {
        let testBody = "https://example.com/test"
        MessagesLaunchStore.save(body: testBody, config: testConfig)

        // First consume should return the request
        let firstConsume = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertNotNil(firstConsume)
        XCTAssertEqual(firstConsume?.body, testBody)

        // Second consume should return nil (already consumed)
        let secondConsume = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertNil(secondConsume, "Consume should remove the request after first read")
        
        if let url = fileURL() {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "File should be deleted after consume")
        }
    }

    func testConsumeReturnsNilWhenNoRequest() {
        let consumed = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertNil(consumed, "Should return nil when no request is stored")
    }

    func testConsumeWithCorruptedData() {
        // Store invalid data
        guard let url = fileURL() else { return }
        try? "invalid json".data(using: .utf8)?.write(to: url)

        let consumed = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertNil(consumed, "Should return nil for corrupted data")

        // Verify it was removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Should remove corrupted data")
    }

    // MARK: - Integration Tests

    func testSaveConsumeRoundtrip() {
        let testBody = "https://secretatomics.com/w/xyz789?v=1&sig=abc&p=def"

        MessagesLaunchStore.save(body: testBody, config: testConfig)
        let consumed = MessagesLaunchStore.consume(config: testConfig)

        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.body, testBody)
        XCTAssertNotNil(consumed?.createdAt)

        // Verify createdAt is recent
        let timeSinceCreation = Date().timeIntervalSince(consumed!.createdAt)
        XCTAssertLessThan(timeSinceCreation, 1.0, "CreatedAt should be very recent")
    }

    func testMultipleSavesOverwritePrevious() {
        MessagesLaunchStore.save(body: "first", config: testConfig)
        MessagesLaunchStore.save(body: "second", config: testConfig)

        let consumed = MessagesLaunchStore.consume(config: testConfig)
        XCTAssertEqual(consumed?.body, "second", "Second save should overwrite first")
    }
}
