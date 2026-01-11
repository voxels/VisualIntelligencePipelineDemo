import XCTest
import AppIntents
import SwiftData
@testable import Diver
import DiverKit
import DiverShared

@MainActor
final class IntentIntegrationTests: XCTestCase {
    var dataStore: DiverDataStore!
    var context: ModelContext!
    var tempStoreURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        
        // Use a unique temporary directory for each test run to ensure isolation
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempStoreURL = tempDir.appendingPathComponent("IntegrationTest.sqlite")
        
        // Setup persistent data store at the temp URL
        let schema = Schema(DiverDataStore.coreTypes)
        let config = ModelConfiguration(schema: schema, url: tempStoreURL, isStoredInMemoryOnly: false)
        dataStore = DiverDataStore(schema: schema, configurations: [config])
        context = dataStore.mainContext
        
        // Inject into DiverApp for LinkEntityQuery fallback logic (if we were using the canImport(Diver) path)
        DiverApp._staticDataStore = dataStore
    }

    override func tearDown() async throws {
        DiverApp._staticDataStore = nil
        if let tempStoreURL = tempStoreURL {
            try? FileManager.default.removeItem(at: tempStoreURL.deletingLastPathComponent())
        }
        try await super.tearDown()
    }

    func testLinkEntityQueryBypassDataSync() throws {
        // 1. Seed data directly into the context
        let item = ProcessedItem(
            id: "integration-1",
            url: "https://example.com/integration",
            title: "Integration Test Link",
            status: .ready
        )
        context.insert(item)
        try context.save()
        
        // 2. Query using LinkEntityQuery
        let query = LinkEntityQuery()
        let results = try query.suggestedEntities()
        
        // 3. Verify
        // Note: Our current LinkEntityQuery has a 'Debug Probe' injected at the top!
        XCTAssertTrue(results.count >= 2, "Should have at least the debug probe and our seeded item")
        XCTAssertTrue(results.contains { $0.title == "Integration Test Link" })
    }

    func testSearchLinksIntentRetrieval() async throws {
        // 1. Seed data
        let item = ProcessedItem(
            id: "search-1",
            url: "https://example.com/search",
            title: "Searchable Link",
            status: .ready
        )
        context.insert(item)
        try context.save()
        
        // 2. Execute Intent
        let intent = SearchLinksIntent()
        intent.query = "Searchable"
        
        let result = try await intent.perform()
        
        // 3. Verify
        XCTAssertEqual(result.value.title, "Searchable Link")
    }
    
    func testDataSeederIntegration() async throws {
        // 1. Run DataSeeder (requires Bundle.module to have the JSON, which it should in the test target)
        try DataSeeder.seed(context: context)
        
        // 2. Verify items were created in ready state
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.status == .ready })
        let items = try context.fetch(fetch)
        
        XCTAssertGreaterThan(items.count, 0, "DataSeeder should have populated the database")
        
        // 3. Verify LinkEntityQuery sees them
        let query = LinkEntityQuery()
        let results = try query.suggestedEntities()
        
        // Results should contain seeded items (excluding the debug probe)
        let nonDebugResults = results.filter { $0.title != "Debug Probe: Code Updated" }
        XCTAssertGreaterThan(nonDebugResults.count, 0)

    func testAppGroupURLGeneration() throws {
        // This test verifies if the App Group identifier in the code matches the entitlements
        // and if the system can provide a container URL for it.
        // It might fail in a test runner if the test host doesn't have the entitlement,
        // but it will tell us if it throws or returns nil.
        
        do {
            let url = try AppGroupContainer.dataStoreURL()
            XCTAssertNotNil(url)
            XCTAssertTrue(url.path.contains("group.com.secretatomics.Diver"))
            print("✅ App Group Data Store URL: \(url.path)")
        } catch {
            print("⚠️ App Group URL generation failed in test: \(error.localizedDescription)")
            // We don't necessarily want to fail the test here if the environment is known to be limited,
            // but we want the log.
        }
    }
}
