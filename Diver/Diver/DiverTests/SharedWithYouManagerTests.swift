import XCTest
import SharedWithYou
@testable import Diver
@testable import DiverKit
import DiverShared

@MainActor
final class SharedWithYouManagerTests: XCTestCase {
    
    var queueStore: MockDiverQueueStore!
    var manager: SharedWithYouManager!
    
    override func setUp() {
        super.setUp()
        // We can use the same /tmp URL for the mock store
        queueStore = MockDiverQueueStore()
        manager = SharedWithYouManager(queueStore: queueStore, isEnabled: false)
    }
    
    func testInitialization() {
        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(manager.highlights.isEmpty)
    }
    
    func testSetEnabled() {
        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)
        
        manager.setEnabled(false)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(manager.highlights.isEmpty)
    }
}

// Simple mock for testing without touching existing mocks
class MockDiverQueueStore: DiverQueueStore {
    var enqueuedItems: [DiverQueueItem] = []

    init() {
        try! super.init(directoryURL: URL(fileURLWithPath: "/tmp"))
    }

    override func enqueue(_ item: DiverQueueItem) throws -> DiverQueueRecord {
        enqueuedItems.append(item)
        let fileURL = URL(fileURLWithPath: "/tmp/\(item.id).json")
        return DiverQueueRecord(item: item, fileURL: fileURL)
    }
}
