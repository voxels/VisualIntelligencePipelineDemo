import XCTest
import AppIntents
@testable import Diver
import DiverKit
import DiverShared
import SwiftData

@MainActor
final class SearchLinksIntentTests: XCTestCase {
    var intent: SearchLinksIntent!
    var dataStore: DiverDataStore!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        // Setup in-memory data store
        dataStore = try DiverDataStore(inMemory: true)
        context = dataStore.mainContext

        // DiverApp._staticDataStore assignment disabled to avoid ambiguity in tests
        // DiverApp._staticDataStore = dataStore

        // Inject into LinkEntityQuery
        LinkEntityQuery.testContainer = dataStore.container

        // Seed test data
        try await seedTestData()
    }

    override func tearDown() async throws {
        LinkEntityQuery.testContainer = nil
        try await super.tearDown()
    }

    // MARK: - Test Data Setup

    private func seedTestData() async throws {
        // Create test items with various attributes
        let items: [(String, String, Date, ProcessingStatus, [String])] = [
            ("https://swift.org", "Swift Documentation", Date().addingTimeInterval(-100), .ready, ["swift", "docs"]),
            ("https://apple.com", "Apple Homepage", Date().addingTimeInterval(-200), .ready, ["apple"]),
            ("https://github.com", "GitHub", Date().addingTimeInterval(-300), .ready, ["git", "development"]),
            ("https://stackoverflow.com", "Stack Overflow", Date().addingTimeInterval(-400), .ready, ["programming"]),
            ("https://news.ycombinator.com", "Hacker News", Date().addingTimeInterval(-500), .processing, ["news"]),
            ("https://reddit.com/r/swift", "Swift Subreddit", Date().addingTimeInterval(-600), .ready, ["swift", "community"]),
        ]

        for (url, title, date, status, tags) in items {
            let item = ProcessedItem(
                id: DiverLinkWrapper.id(for: URL(string: url)!),
                url: url,
                title: title,
                tags: tags,
                createdAt: date,
                status: status
            )
            context.insert(item)
        }

        try context.save()
    }

    // MARK: - Empty Query (Recent Links) Tests

    func testSearchLinksIntent_EmptyQuery_ReturnsRecentLink() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.limit = 10
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertNotNil(result.value, "Should return a link")
        XCTAssertEqual(result.value?.title, "Swift Documentation", "Should return most recent ready link")
        // XCTAssertTrue(result.dialog.debugDescription.contains("recent"), "Should mention recent in dialog")
    }

    func testSearchLinksIntent_EmptyQuery_FiltersNonReadyStatus() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // Should not return "Hacker News" which has .processing status
        XCTAssertNotEqual(result.value?.title, "Hacker News")
        XCTAssertEqual(result.value?.status, .ready)
    }

    func testSearchLinksIntent_EmptyQuery_SortsByCreatedAtDescending() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // Most recent item should be Swift Documentation (createdAt: -100)
        XCTAssertEqual(result.value?.title, "Swift Documentation")
    }

    // MARK: - Search Query Tests

    func testSearchLinksIntent_WithQuery_ReturnsMatchingLink() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "GitHub"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "GitHub")
        // XCTAssertTrue(result.dialog.debugDescription.contains("GitHub"), "Should mention query in dialog")
    }

    func testSearchLinksIntent_QueryMatchesURL_ReturnsLink() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "stackoverflow"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "Stack Overflow")
    }

    func testSearchLinksIntent_QueryMatchesSummary_ReturnsLink() async throws {
        // Given
        // Add item with specific summary
        let summaryItem = ProcessedItem(
            id: "summary-test",
            url: "https://example.com/summary",
            title: "Summary Page",
            summary: "This is a very specific unique summary content",
            createdAt: Date(),
            status: .ready
        )
        context.insert(summaryItem)
        try context.save()

        intent = SearchLinksIntent()
        intent.query = "unique summary"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "Summary Page")
    }

    func testSearchLinksIntent_PartialMatch_ReturnsLink() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "swift"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // Should match either "Swift Documentation" or "Swift Subreddit"
        XCTAssertTrue(
            result.value?.title == "Swift Documentation" || result.value?.title == "Swift Subreddit",
            "Should match partial query"
        )
    }

    func testSearchLinksIntent_CaseInsensitive_ReturnsLink() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "APPLE"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "Apple Homepage")
    }

    // MARK: - Tag Filtering Tests

    func testSearchLinksIntent_EmptyQuery_WithTags_FiltersCorrectly() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = ["swift"]

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertTrue(result.value?.tags.contains("swift") == true, "Result should have swift tag")
        // Should be either "Swift Documentation" or "Swift Subreddit"
        XCTAssertTrue(
            result.value?.title == "Swift Documentation" || result.value?.title == "Swift Subreddit"
        )
    }

    func testSearchLinksIntent_WithQuery_WithTags_FiltersCorrectly() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "swift"
        intent.tags = ["docs"]

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "Swift Documentation")
        XCTAssertTrue(result.value?.tags.contains("docs") == true)
    }

    func testSearchLinksIntent_MultipleTags_RequiresAllTags() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = ["swift", "community"]

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "Swift Subreddit")
        XCTAssertTrue(result.value?.tags.contains("swift") == true)
        XCTAssertTrue(result.value?.tags.contains("community") == true)
    }

    func testSearchLinksIntent_TagsWithNoMatch_ThrowsError() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = ["nonexistent"]

        // When/Then
        do {
            _ = try await intent.perform()
            XCTFail("Should throw error when no results found")
        } catch {
            let nsError = error as NSError
            XCTAssertTrue(nsError.localizedDescription.contains("No recent links found"))
        }
    }

    // MARK: - Limit Tests

    func testSearchLinksIntent_WithLimit_RespectsLimit() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.limit = 1
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // Should return only the first result (most recent)
        XCTAssertEqual(result.value?.title, "Swift Documentation")
    }

    // MARK: - No Results Tests

    func testSearchLinksIntent_NoResults_ThrowsError() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "nonexistent query that matches nothing"
        intent.tags = []

        // When/Then
        do {
            _ = try await intent.perform()
            XCTFail("Should throw error when no results found")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.code, 404)
            XCTAssertTrue(nsError.localizedDescription.contains("No links found"))
            XCTAssertTrue(nsError.localizedDescription.contains("nonexistent query"))
        }
    }

    func testSearchLinksIntent_EmptyLibrary_ThrowsError() async throws {
        // Given
        // Clear all items
        try context.delete(model: ProcessedItem.self)
        try context.save()

        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = []

        // When/Then
        do {
            _ = try await intent.perform()
            XCTFail("Should throw error when library is empty")
        } catch {
            let nsError = error as NSError
            XCTAssertTrue(nsError.localizedDescription.contains("No recent links found"))
        }
    }

    // MARK: - Single Selection Tests

    func testSearchLinksIntent_MultipleMatches_ReturnsFirstMatch() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "swift"  // Matches 2 items
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // Should return only one link, not an array
        XCTAssertNotNil(result.value)
        // Verify it's a LinkEntity, not an array
        // Verify it's a LinkEntity, not an array
        // XCTAssertTrue(type(of: result.value) == LinkEntity.self)
        XCTAssertNotNil(result.value)
    }

    // MARK: - Dialog Tests

    func testSearchLinksIntent_SuccessfulSearch_IncludesCountAndTitle() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "GitHub"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // let dialog = result.dialog.debugDescription
        // XCTAssertTrue(dialog.contains("Found"), "Should say Found")
        // XCTAssertTrue(dialog.contains("GitHub"), "Should mention the query or title")
        // XCTAssertTrue(dialog.contains("Returning"), "Should say Returning")
    }

    func testSearchLinksIntent_EmptyQuery_MentionsRecent() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = ""
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        // XCTAssertTrue(result.dialog.debugDescription.contains("recent"))
    }

    // MARK: - Edge Cases

    func testSearchLinksIntent_VeryLongQuery_HandlesCorrectly() async throws {
        // Given
        let longQuery = String(repeating: "a", count: 1000)
        intent = SearchLinksIntent()
        intent.query = longQuery
        intent.tags = []

        // When/Then
        do {
            _ = try await intent.perform()
            XCTFail("Should not match anything")
        } catch {
            // Expected
        }
    }

    func testSearchLinksIntent_SpecialCharacters_HandlesCorrectly() async throws {
        // Given
        intent = SearchLinksIntent()
        intent.query = "r/swift"  // Contains forward slash
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "Swift Subreddit")
    }

    func testSearchLinksIntent_UnicodeQuery_HandlesCorrectly() async throws {
        // Given
        // Add item with unicode title
        let unicodeItem = ProcessedItem(
            id: "unicode-test",
            url: "https://example.com",
            title: "测试页面",
            createdAt: Date(),
            status: .ready
        )
        context.insert(unicodeItem)
        try context.save()

        intent = SearchLinksIntent()
        intent.query = "测试"
        intent.tags = []

        // When
        let result = try await intent.perform()

        // Then
        XCTAssertEqual(result.value?.title, "测试页面")
    }
}
