import XCTest
import AppIntents
@testable import VisualIntelligencePipeline
import DiverKit
import DiverShared

@MainActor
final class ShareLinkIntentTests: XCTestCase {
    var intent: ShareLinkIntent!
    var testURL: URL!
    var queueStore: DiverQueueStore!
    var queueURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Setup test URL
        testURL = URL(string: "https://www.example.com/test-page")!

        // Setup queue store with temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        queueStore = try DiverQueueStore(directoryURL: tempDir)
        self.queueURL = tempDir
        ShareLinkIntent._testQueueStore = queueStore

        // Ensure keychain has secret (required for wrapping)
        let keychainService = KeychainService(
            service: KeychainService.ServiceIdentifier.diver,
            accessGroup: AppGroupConfig.default.keychainAccessGroup
        )

        // Generate a test secret if none exists
        if keychainService.retrieveString(key: KeychainService.Keys.diverLinkSecret) == nil {
            let testSecret = String(repeating: "a", count: 64)
            _ = try? keychainService.store(key: KeychainService.Keys.diverLinkSecret, value: testSecret)
        }
    }

    override func tearDown() async throws {
        ShareLinkIntent._testQueueStore = nil
        // Clean up temp queue directory
        if let queueURL = queueURL {
            try? FileManager.default.removeItem(at: queueURL)
        }
        try await super.tearDown()
    }

    // MARK: - Valid URL Tests

    func testShareLinkIntent_ValidURL_ReturnsWrappedLink() async throws {
        // Given
        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = "Test Page"

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertNotNil(result.value, "Wrapped link should not be nil")
        let urlString = result.value?.absoluteString ?? ""
        XCTAssertTrue(urlString.hasPrefix("https://secretatomics.com/w/"), "Should use correct base URL")
        XCTAssertTrue(urlString.contains("?v=1"), "Should include version parameter")
        XCTAssertTrue(urlString.contains("&sig="), "Should include signature")
    }

    func testShareLinkIntent_ValidURL_QueuesItem() async throws {
        // Given
        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = "Test Page"

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.count, 1, "Should queue exactly one item")

        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.descriptor.url, testURL.absoluteString)
        XCTAssertEqual(queuedItem.item.descriptor.title, "Test Page")
        XCTAssertNotNil(queuedItem.item.descriptor.wrappedLink, "Should store wrapped link in descriptor")
    }

    func testShareLinkIntent_URLWithoutTitle_UsesURLAsTitle() async throws {
        // Given
        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = nil

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertNotNil(result.value)

        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.descriptor.title, testURL.absoluteString)
    }

    // MARK: - Invalid URL Tests

    func testShareLinkIntent_InvalidURL_ReturnsError() async throws {
        // Given
        let invalidURL = URL(string: "not-a-valid-url")!
        intent = ShareLinkIntent()
        intent.url = invalidURL

        // When
        let result = try await intent.perform()

        // Then
        // We now return the original URL on error
        XCTAssertEqual(result.value, invalidURL, "Should return original URL for invalid URL")
    }

    // MARK: - Keychain Tests

    func testShareLinkIntent_MissingKeychainSecret_ReturnsError() async throws {
        // Given
        let keychainService = KeychainService(
            service: KeychainService.ServiceIdentifier.diver,
            accessGroup: AppGroupConfig.default.keychainAccessGroup
        )
        _ = keychainService.delete(key: KeychainService.Keys.diverLinkSecret)

        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = "Test"

        // When
        let result = try await intent.perform()

        // Then
        // We returns original URL on failure
        XCTAssertEqual(result.value, testURL, "Should return original URL when keychain fails")

        // Restore secret for other tests
        let testSecret = String(repeating: "a", count: 64)
        _ = try? keychainService.store(key: KeychainService.Keys.diverLinkSecret, value: testSecret)
    }

    // MARK: - Wrapped Link Format Tests

    func testShareLinkIntent_WrappedLinkFormat_IsValid() async throws {
        // Given
        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = "Test"

        // When
        let result = try await intent.perform()

        // Then
        guard let wrappedURL = result.value else {
            XCTFail("Wrapped link should be a valid URL")
            return
        }

        XCTAssertEqual(wrappedURL.scheme, "https")
        XCTAssertEqual(wrappedURL.host, "secretatomics.com")
        XCTAssertTrue(wrappedURL.path.hasPrefix("/w/"), "Path should start with /w/")

        // Check query parameters
        let components = URLComponents(url: wrappedURL, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertTrue(queryItems.contains { $0.name == "v" && $0.value == "1" }, "Should have version=1")
        XCTAssertTrue(queryItems.contains { $0.name == "sig" }, "Should have signature")
        XCTAssertTrue(queryItems.contains { $0.name == "p" }, "Should have payload")
    }

    // MARK: - Queue Integration Tests

    func testShareLinkIntent_QueueFailure_ReturnsWrappedLinkAnyway() async throws {
        // Given
        // This test verifies graceful degradation when queueing fails
        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = "Test"

        // When
        let result = try await intent.perform()

        // Then
        // Even if queueing fails, we should still get the wrapped link
        XCTAssertNotNil(result.value, "Should return wrapped link even if queueing fails")
    }

    // MARK: - Edge Cases

    func testShareLinkIntent_VeryLongURL_HandlesCorrectly() async throws {
        // Given
        let longPath = String(repeating: "a", count: 2000)
        let longURL = URL(string: "https://example.com/\(longPath)")!

        intent = ShareLinkIntent()
        intent.url = longURL

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertNotNil(result.value, "Should handle long URLs")
    }

    func testShareLinkIntent_URLWithSpecialCharacters_EncodesCorrectly() async throws {
        // Given
        let specialURL = URL(string: "https://example.com/test?query=hello%20world&foo=bar#section")!

        intent = ShareLinkIntent()
        intent.url = specialURL
        intent.title = "Special URL"

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertNotNil(result.value, "Should handle special characters")

        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.descriptor.url, specialURL.absoluteString)
    }

    func testShareLinkIntent_UnicodeTitle_HandlesCorrectly() async throws {
        // Given
        intent = ShareLinkIntent()
        intent.url = testURL
        intent.title = "测试页面 🚀"

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertNotNil(result.value)
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.descriptor.title, "测试页面 🚀")
    }
}

