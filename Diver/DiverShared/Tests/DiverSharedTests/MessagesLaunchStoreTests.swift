import XCTest
@testable import DiverShared

final class MessagesLaunchStoreTests: XCTestCase {

    var testConfig: AppGroupConfig!
    var testDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()

        // Create a test suite name for isolated UserDefaults
        testSuiteName = "test.MessagesLaunchStore.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!

        // Create test config (doesn't need real app group for UserDefaults tests)
        testConfig = AppGroupConfig(
            groupIdentifier: "test.group",
            keychainAccessGroup: "test.keychain",
            cloudKitContainers: []
        )
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        testConfig = nil
        testSuiteName = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    func testSaveStoresMessageLaunchRequest() {
        let testBody = "https://secretatomics.com/w/abc123"

        MessagesLaunchStore.save(body: testBody, config: testConfig, defaults: testDefaults)

        // Verify it was stored
        let key = "Diver.MessagesLaunchRequest"
        let storedData = testDefaults.data(forKey: key)
        XCTAssertNotNil(storedData, "Should store data in UserDefaults")

        // Verify it can be decoded
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try? decoder.decode(MessagesLaunchRequest.self, from: storedData!)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.body, testBody)
    }

    func testSaveTrimsLongBody() {
        let longBody = String(repeating: "a", count: 3000)

        MessagesLaunchStore.save(body: longBody, config: testConfig, defaults: testDefaults)

        let consumed = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.body?.count, 2000, "Should trim to 2000 characters")
    }

    func testSaveWithNilBody() {
        MessagesLaunchStore.save(body: nil, config: testConfig, defaults: testDefaults)

        let consumed = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertNotNil(consumed, "Should store request even with nil body")
        XCTAssertNil(consumed?.body)
    }

    // MARK: - Consume Tests

    func testConsumeRetrievesAndRemovesRequest() {
        let testBody = "https://example.com/test"
        MessagesLaunchStore.save(body: testBody, config: testConfig, defaults: testDefaults)

        // First consume should return the request
        let firstConsume = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertNotNil(firstConsume)
        XCTAssertEqual(firstConsume?.body, testBody)

        // Second consume should return nil (already consumed)
        let secondConsume = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertNil(secondConsume, "Consume should remove the request after first read")
    }

    func testConsumeReturnsNilWhenNoRequest() {
        let consumed = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertNil(consumed, "Should return nil when no request is stored")
    }

    func testConsumeWithCorruptedData() {
        // Store invalid data
        let key = "Diver.MessagesLaunchRequest"
        testDefaults.set("invalid json".data(using: .utf8), forKey: key)

        let consumed = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertNil(consumed, "Should return nil for corrupted data")

        // Verify it was removed
        let remainingData = testDefaults.data(forKey: key)
        XCTAssertNil(remainingData, "Should remove corrupted data")
    }

    // MARK: - Integration Tests

    func testSaveConsumeRoundtrip() {
        let testBody = "https://secretatomics.com/w/xyz789?v=1&sig=abc&p=def"

        MessagesLaunchStore.save(body: testBody, config: testConfig, defaults: testDefaults)
        let consumed = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)

        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.body, testBody)
        XCTAssertNotNil(consumed?.createdAt)

        // Verify createdAt is recent
        let timeSinceCreation = Date().timeIntervalSince(consumed!.createdAt)
        XCTAssertLessThan(timeSinceCreation, 1.0, "CreatedAt should be very recent")
    }

    func testMultipleSavesOverwritePrevious() {
        MessagesLaunchStore.save(body: "first", config: testConfig, defaults: testDefaults)
        MessagesLaunchStore.save(body: "second", config: testConfig, defaults: testDefaults)

        let consumed = MessagesLaunchStore.consume(config: testConfig, defaults: testDefaults)
        XCTAssertEqual(consumed?.body, "second", "Second save should overwrite first")
    }
}
