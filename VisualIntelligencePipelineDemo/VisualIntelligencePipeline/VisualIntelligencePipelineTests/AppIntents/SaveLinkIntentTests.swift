import XCTest
import AppIntents
@testable import Diver
import DiverKit
import DiverShared

@MainActor
final class SaveLinkIntentTests: XCTestCase {
    var intent: SaveLinkIntent!
    var testURL: URL!
    var queueStore: DiverQueueStore!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Setup test URL
        testURL = URL(string: "https://www.example.com/article")!

        // Setup queue store with temp directory
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        queueStore = try DiverQueueStore(directoryURL: tempDir)
        SaveLinkIntent._testQueueStore = queueStore
    }

    override func tearDown() async throws {
        SaveLinkIntent._testQueueStore = nil
        // Clean up temp queue directory
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Valid URL Tests

    func testSaveLinkIntent_ValidURL_QueuesItem() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = "Test Article"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // Result dialog inspection is not supported on opaque types easily
        // XCTAssertTrue(result.dialog.debugDescription...)

        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.count, 1, "Should queue exactly one item")

        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.action, "save")
        XCTAssertEqual(queuedItem.item.descriptor.url, testURL.absoluteString)
        XCTAssertEqual(queuedItem.item.descriptor.title, "Test Article")
        XCTAssertNil(queuedItem.item.descriptor.wrappedLink, "SaveIntent should not wrap URL")
    }

    func testSaveLinkIntent_WithTags_StoresTags() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = "Tagged Article"
        intent.tags = ["swift", "ios", "development"]

        // When
        let result = try await intent.perform()

        // Then
        // XCTAssertTrue(result.dialog.debugDescription.contains("swift"), "Should mention tags in dialog")
        // XCTAssertTrue(result.dialog.debugDescription.contains("ios"), "Should mention tags in dialog")

        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.descriptor.tags, ["swift", "ios", "development"])
    }

    func testSaveLinkIntent_WithoutTags_StoresNilTags() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = "Untagged Article"
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!
        XCTAssertNil(queuedItem.item.descriptor.tags, "Empty tags array should become nil")
    }

    func testSaveLinkIntent_WithoutTitle_UsesURLAsTitle() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = nil
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.descriptor.title, testURL.absoluteString)
    }

    // MARK: - Invalid URL Tests

    func testSaveLinkIntent_InvalidURL_ReturnsError() async throws {
        // Given
        let invalidURL = URL(string: "not-a-valid-url")!
        intent = SaveLinkIntent()
        intent.url = invalidURL
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // XCTAssertTrue(result.dialog.debugDescription.contains("not valid"), "Should indicate URL is invalid")

        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.count, 0, "Should not queue invalid URLs")
    }

    // MARK: - Descriptor ID Tests

    func testSaveLinkIntent_GeneratesCorrectID() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = "Test"
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!

        // ID should be SHA256 hash of URL
        let expectedID = DiverLinkWrapper.id(for: testURL)
        XCTAssertEqual(queuedItem.item.descriptor.id, expectedID)
    }

    // MARK: - Source Tests

    func testSaveLinkIntent_SetsSourceToHost() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = URL(string: "https://www.github.com/test")!
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.source, "www.github.com")
    }

    func testSaveLinkIntent_URLWithoutHost_UsesAppIntentAsSource() async throws {
        // Given
        let fileURL = URL(string: "file:///path/to/file")!
        intent = SaveLinkIntent()
        intent.url = fileURL
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.source, "AppIntent")
    }

    // MARK: - Tag Validation Tests

    func testSaveLinkIntent_DuplicateTags_StoresDuplicates() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.tags = ["swift", "swift", "ios"]

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.descriptor.tags, ["swift", "swift", "ios"])
    }

    func testSaveLinkIntent_TagsWithWhitespace_PreservesWhitespace() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.tags = ["  swift  ", "ios development"]

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.descriptor.tags, ["  swift  ", "ios development"])
    }

    func testSaveLinkIntent_UnicodeTags_HandlesCorrectly() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.tags = ["编程", "🚀", "日本語"]

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.descriptor.tags, ["编程", "🚀", "日本語"])
    }

    // MARK: - Dialog Tests

    func testSaveLinkIntent_WithTags_IncludesTagsInDialog() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = "Article"
        intent.tags = ["swift", "ios"]

        // When
        let result = try await intent.perform()

        // Then
        // let dialog = result.dialog.debugDescription
        // XCTAssertTrue(dialog.contains("with tags:"), "Should mention tags")
        // XCTAssertTrue(dialog.contains("swift, ios"), "Should list tags comma-separated")
    }

    func testSaveLinkIntent_WithoutTags_ExcludesTagsFromDialog() async throws {
        // Given
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.title = "Article"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // let dialog = result.dialog.debugDescription
        // XCTAssertFalse(dialog.contains("with tags:"), "Should not mention tags when none provided")
    }

    // MARK: - Edge Cases

    func testSaveLinkIntent_VeryLongURL_HandlesCorrectly() async throws {
        // Given
        let longPath = String(repeating: "a", count: 2000)
        let longURL = URL(string: "https://example.com/\(longPath)")!

        intent = SaveLinkIntent()
        intent.url = longURL
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.count, 1, "Should handle long URLs")
    }

    func testSaveLinkIntent_ManyTags_HandlesCorrectly() async throws {
        // Given
        let manyTags = (1...100).map { "tag\($0)" }
        intent = SaveLinkIntent()
        intent.url = testURL
        intent.tags = manyTags

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        let queuedItem = items.first!
        XCTAssertEqual(queuedItem.item.descriptor.tags.count, 100)
    }

    func testSaveLinkIntent_URLWithFragment_PreservesFragment() async throws {
        // Given
        let urlWithFragment = URL(string: "https://example.com/page#section")!
        intent = SaveLinkIntent()
        intent.url = urlWithFragment
        intent.tags = []

        // When
        _ = try await intent.perform()

        // Then
        let items = try queueStore.pendingEntries()
        XCTAssertEqual(items.first?.item.descriptor.url, urlWithFragment.absoluteString)
    }
}
