import XCTest
import SwiftData
import CoreLocation
import DiverShared
@testable import DiverKit

@MainActor
final class PipelinePerformanceTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
    }
    
    // MARK: - SwiftData Bulk Insert
    
    func testBulkInsert100Items() throws {
        measure {
            let items = (0..<100).map { i in
                makeProcessedItem(
                    id: "perf-\(i)-\(UUID().uuidString)",
                    title: "Item \(i)",
                    status: .ready,
                    sessionID: "perf-session",
                    tags: ["tag1", "tag2", "tag3"]
                )
            }
            
            for item in items {
                modelContext.insert(item)
            }
            
            try? modelContext.save()
        }
    }
    
    // MARK: - SwiftData Bulk Fetch
    
    func testBulkFetch500Items() throws {
        // Setup: Insert 500 items first
        for i in 0..<500 {
            let item = makeProcessedItem(
                id: "fetch-perf-\(i)",
                title: "Item \(i)",
                status: i % 5 == 0 ? .processing : .ready,
                sessionID: "fetch-session-\(i % 10)"
            )
            modelContext.insert(item)
        }
        try modelContext.save()
        
        // Measure fetch performance
        measure {
            let descriptor = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.status == .ready },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let _ = try? modelContext.fetch(descriptor)
        }
    }
    
    // MARK: - Session Clustering
    
    func testCluster500Items() {
        let service = SessionClusteringService()
        let now = Date()
        
        // Generate 500 assets spread across ~10 locations over 48 hours
        let assets = (0..<500).map { i in
            let timeOffset = Double(i) * 345.6 // ~48 hours total
            let locationIndex = i % 10
            let locations: [(Double, Double)] = [
                (40.7128, -74.0060),  // NYC
                (34.0522, -118.2437), // LA
                (41.8781, -87.6298),  // Chicago
                (29.7604, -95.3698),  // Houston
                (33.4484, -112.0740), // Phoenix
                (40.7128, -74.0060),  // NYC again
                (34.0522, -118.2437), // LA again
                (47.6062, -122.3321), // Seattle
                (25.7617, -80.1918),  // Miami
                (39.7392, -104.9903)  // Denver
            ]
            let loc = locations[locationIndex]
            return makeImportedAsset(
                creationDate: now.addingTimeInterval(timeOffset),
                latitude: loc.0,
                longitude: loc.1
            )
        }
        
        measure {
            let _ = service.clusterItems(assets)
        }
    }
    
    // MARK: - Sort & Filter Performance
    
    func testSortAndFilter200Items() {
        let viewModel = SidebarViewModel()
        viewModel.searchText = "test"
        
        let items = (0..<200).map { i in
            makeProcessedItem(
                id: "filter-\(i)",
                title: i % 3 == 0 ? "Test Item \(i)" : "Other Item \(i)",
                status: i % 10 == 0 ? .processing : .ready,
                tags: i % 2 == 0 ? ["test", "tag"] : ["other"]
            )
        }
        
        measure {
            let _ = viewModel.sortAndFilter(items: items)
        }
    }
    
    // MARK: - Queue Processing Throughput
    
    func testQueueStoreThroughput() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try DiverQueueStore(directoryURL: tempDir)
        
        measure {
            // Enqueue 50 items
            for i in 0..<50 {
                let descriptor = makeDescriptor(
                    id: UUID().uuidString,
                    url: "https://perf-\(i).com",
                    title: "Perf Item \(i)"
                )
                let item = DiverQueueItem(action: "save", descriptor: descriptor)
                try? store.enqueue(item)
            }
            
            // Dequeue all
            let pending = try? store.pendingEntries()
            for entry in pending ?? [] {
                try? store.remove(entry)
            }
        }
    }
    
    // MARK: - SwiftData Relationship Traversal
    
    func testSessionItemRelationshipTraversal() throws {
        // Create 10 sessions with 20 items each
        for s in 0..<10 {
            let session = makeSession(sessionID: "rel-session-\(s)", title: "Session \(s)")
            modelContext.insert(session)
            
            for i in 0..<20 {
                let item = makeProcessedItem(
                    id: "rel-item-\(s)-\(i)",
                    title: "Item \(i)",
                    sessionID: session.sessionID
                )
                item.session = session
                modelContext.insert(item)
            }
        }
        try modelContext.save()
        
        measure {
            // Fetch all sessions and traverse to their items
            let descriptor = FetchDescriptor<SessionMetadata>()
            guard let sessions = try? modelContext.fetch(descriptor) else { return }
            
            var totalItems = 0
            for session in sessions {
                totalItems += session.items?.count ?? 0
            }
            
            XCTAssertEqual(totalItems, 200)
        }
    }
}
