import XCTest
import SwiftData
@testable import DiverKit

@MainActor
final class ArchitectureTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var service: LocalPipelineService!

    override func setUp() async throws {
        let schema = Schema([ProcessedItem.self, SessionMetadata.self, SessionCollection.self, UserConcept.self, LocalInput.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)
        service = LocalPipelineService(modelContext: modelContext)
    }

    func testDiverObjectConformance() {
        // Given: Models of different types
        let item = ProcessedItem(id: "item-1", url: nil, title: "Test Item")
        let session = SessionMetadata(sessionID: "session-1", title: "Test Session")
        let collection = SessionCollection(name: "Test Collection", sessionIDs: [])

        // Then: They should all conform to DiverObject and provide displayTitle
        XCTAssertTrue(item is any DiverObject)
        XCTAssertTrue(session is any DiverObject)
        XCTAssertTrue(collection is any DiverObject)
        
        XCTAssertEqual(item.displayTitle, "Test Item")
        XCTAssertEqual(session.displayTitle, "Test Session")
        XCTAssertEqual(collection.displayTitle, "Test Collection")
    }

    func testSessionItemRelationship() throws {
        // Given: A session and an item
        let session = SessionMetadata(sessionID: "session-1", title: "Test Session")
        let item = ProcessedItem(id: "item-1", url: nil, title: "Test Item")
        modelContext.insert(session)
        modelContext.insert(item)
        
        // When: We link them
        item.session = session
        try modelContext.save()
        
        // Then: The relationship should be traversable from both sides
        XCTAssertEqual(item.session?.sessionID, "session-1")
        XCTAssertTrue(session.items?.contains(where: { $0.id == "item-1" }) ?? false)
    }

    func testCascadeDelete() throws {
        // Given: A session with an item
        let session = SessionMetadata(sessionID: "session-cascade", title: "Test Cascade")
        let item = ProcessedItem(id: "item-cascade", url: nil, title: "Child Item")
        modelContext.insert(session)
        modelContext.insert(item)
        item.session = session
        try modelContext.save()
        
        // When: We delete the session
        modelContext.delete(session)
        try modelContext.save()
        
        // Then: The item should also be deleted (cascade)
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == "item-cascade" })
        let items = try modelContext.fetch(fetch)
        XCTAssertTrue(items.isEmpty, "Item should have been deleted via cascade")
    }

    func testRelationshipReconciliation() async throws {
        // Given: Records with matching IDs but no pointers (simulating old data)
        let sessionID = "recon-session"
        let session = SessionMetadata(sessionID: sessionID, title: "Recon Session")
        let item = ProcessedItem(id: "recon-item", url: nil, title: "Recon Item")
        item.sessionID = sessionID // Set the ID but not the pointer
        
        modelContext.insert(session)
        modelContext.insert(item)
        try modelContext.save()
        
        // When: We run reconciliation
        await service.reconcileRelationships()
        
        // Then: The pointer should be established
        XCTAssertNotNil(item.session, "Relationship should be reconciled")
        XCTAssertEqual(item.session?.sessionID, sessionID)
    }
    
    // =========================================================================
    // MARK: - ModelContext Thread Safety Architecture Guards
    // =========================================================================
    //
    // These tests scan source files to prevent regression of concurrent
    // ModelContext access patterns that caused EXC_BAD_ACCESS crashes.
    
    /// Guard: ViewModels must NOT call processItemImmediately — use processItemByID instead.
    /// processItemImmediately uses the service's shared ModelContext, which is unsafe
    /// when called from UI code that may trigger multiple concurrent calls.
    func testNoProcessItemImmediatelyCallsFromViewModels() throws {
        let viewModelDir = findSourcesDirectory()?.appendingPathComponent("ViewModel")
        guard let dir = viewModelDir, FileManager.default.fileExists(atPath: dir.path) else {
            // Skip if we can't find the directory (CI environments)
            return
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        
        var violations: [String] = []
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            if content.contains("processItemImmediately") {
                violations.append(file.lastPathComponent)
            }
        }
        
        XCTAssertTrue(violations.isEmpty,
            "ViewModels must use processItemByID (private ModelContext) instead of processItemImmediately (shared context). " +
            "Violations: \(violations.joined(separator: ", "))")
    }
    
    /// Guard: No for-loop should spawn multiple Tasks that each call processItemByID.
    /// Session-level operations must serialize reprocessing into a single Task.detached.
    func testNoForLoopTaskSpawningInViewModels() throws {
        let viewModelDir = findSourcesDirectory()?.appendingPathComponent("ViewModel")
        guard let dir = viewModelDir, FileManager.default.fileExists(atPath: dir.path) else {
            return
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        
        var violations: [String] = []
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            for (i, line) in lines.enumerated() {
                // Detect pattern: `for ... in ... {` followed by `Task {` within 5 lines
                if line.contains("for ") && line.contains(" in ") && line.contains("{") {
                    let lookAhead = lines[i..<min(i + 6, lines.count)].joined(separator: "\n")
                    if lookAhead.contains("Task {") && lookAhead.contains("processItem") {
                        violations.append("\(file.lastPathComponent):\(i + 1)")
                    }
                }
            }
        }
        
        XCTAssertTrue(violations.isEmpty,
            "For-loops must NOT spawn individual Tasks per item for reprocessing. " +
            "Collect IDs and use a single Task.detached with sequential loop. " +
            "Violations: \(violations.joined(separator: ", "))")
    }
    
    // MARK: - Helpers
    
    /// Finds the DiverKit/Sources/DiverKit directory by walking up from the test bundle.
    private func findSourcesDirectory() -> URL? {
        // The test bundle is at DiverKit/Tests/DiverKitTests
        // Sources are at DiverKit/Sources/DiverKit
        let testBundle = Bundle(for: type(of: self))
        var url = testBundle.bundleURL
        
        // Walk up to find the DiverKit package root
        for _ in 0..<10 {
            let candidate = url.appendingPathComponent("DiverKit/Sources/DiverKit")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            // Also try current level
            let sourcesCandidate = url.appendingPathComponent("Sources/DiverKit")
            if FileManager.default.fileExists(atPath: sourcesCandidate.path) {
                return sourcesCandidate
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
}
