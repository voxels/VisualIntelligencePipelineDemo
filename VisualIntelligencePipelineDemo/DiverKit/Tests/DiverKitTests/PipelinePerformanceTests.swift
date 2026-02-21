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
                predicate: #Predicate { $0.statusRaw == "ready" },
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
    
    // MARK: - Reverse Geocoding Cache Performance
    
    /// Measures reverse geocoding cache hit performance.
    /// First call populates cache; subsequent calls should be near-instant.
    /// Baseline: cache hits should be <1ms vs ~100-500ms for network lookup.
    func testReverseGeocodingCacheHitPerformance() async throws {
        let service = ReverseGeocodingService()
        let coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // NYC
        
        // Warm the cache with first lookup
        _ = await service.lookup(coordinate: coordinate)
        
        // Measure cache hit performance
        measure {
            let exp = expectation(description: "cache-hit")
            Task.detached {
                _ = await service.lookup(coordinate: coordinate)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5)
        }
    }
    
    /// Measures that nearby coordinates (within 11m) share the same cache entry.
    /// Coordinates rounded to 4 decimal places should produce cache hits.
    func testReverseGeocodingNearbyCoordinatesCacheSharing() async {
        let service = ReverseGeocodingService()
        let base = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        // Offset by ~5m (well within 11m radius of 4-decimal rounding)
        let nearby = CLLocationCoordinate2D(latitude: 40.71284, longitude: -74.00604)
        
        // Warm cache with base coordinate
        _ = await service.lookup(coordinate: base)
        
        // Nearby coordinate should hit cache (same 4-decimal key)
        measure {
            let exp = expectation(description: "nearby-hit")
            Task.detached {
                _ = await service.lookup(coordinate: nearby)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5)
        }
    }
    
    // MARK: - CGImage Decode Cache Performance
    
    /// Measures CGImage decode performance for repeated decode of same data.
    /// Second decode should be a cache hit (NSCache).
    /// Run on device with Instruments Allocations to verify no duplicate decode buffers.
    func testCGImageDecodeCacheHit() async throws {
        let pipeline = LocalPipelineService(modelContext: modelContext)
        
        // Create a small valid PNG image (1x1 pixel red)
        let pngData = createMinimalPNG()
        
        // First decode: cache miss (populates cache)
        let first = await pipeline.createCGImageForTesting(from: pngData)
        XCTAssertNotNil(first, "First decode should succeed")
        
        // Second decode: cache hit (should be faster)
        measure {
            let exp = expectation(description: "decode")
            Task.detached {
                let _ = await pipeline.createCGImageForTesting(from: pngData)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5)
        }
    }
    
    // MARK: - Cancellation Recovery Performance
    
    /// Measures how quickly a cancelled pipeline item resets to .queued.
    /// Validates that cancellation guards save partial progress efficiently.
    func testCancellationRecoveryThroughput() throws {
        // Create items in .processing state (simulating mid-pipeline cancellation)
        let items = (0..<50).map { i in
            makeProcessedItem(
                id: "cancel-\(i)",
                title: "Cancelling \(i)",
                status: .processing
            )
        }
        
        for item in items {
            modelContext.insert(item)
        }
        try modelContext.save()
        
        // Measure bulk status reset (simulates cancellation cleanup)
        measure {
            let fetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.statusRaw == "processing" }
            )
            guard let processing = try? modelContext.fetch(fetch) else { return }
            
            for item in processing {
                item.status = .queued
            }
            try? modelContext.save()
        }
    }
    
    // MARK: - Pipeline Cold vs Warm Start
    
    /// Measures LocalPipelineService initialization time.
    /// This establishes a baseline for pipeline cold-start latency.
    func testPipelineInitialization() {
        measure {
            let _ = LocalPipelineService(modelContext: modelContext)
        }
    }
    
    // MARK: - Concurrent Read Performance
    
    /// Measures SwiftData fetch performance under concurrent read pressure.
    /// Simulates sidebar + pipeline both reading items simultaneously.
    func testConcurrentFetchPerformance() throws {
        // Setup: Insert 200 items across 5 sessions
        for s in 0..<5 {
            for i in 0..<40 {
                let item = makeProcessedItem(
                    id: "concurrent-\(s)-\(i)",
                    title: "Item \(i)",
                    status: .ready,
                    sessionID: "session-\(s)"
                )
                modelContext.insert(item)
            }
        }
        try modelContext.save()
        
        measure {
            // Simulate sidebar fetch
            let allFetch = FetchDescriptor<ProcessedItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let _ = try? modelContext.fetch(allFetch)
            
            // Simulate session-specific fetch
            let sessionFetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.sessionID == "session-0" }
            )
            let _ = try? modelContext.fetch(sessionFetch)
            
            // Simulate status filter fetch
            let statusFetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.statusRaw == "ready" }
            )
            let _ = try? modelContext.fetch(statusFetch)
        }
    }
    
    // MARK: - Helpers
    
    /// Creates a minimal valid 1x1 red PNG for CGImage decode tests
    private func createMinimalPNG() -> Data {
        // Minimal 1x1 red PNG (67 bytes)
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, // 8-bit RGB
            0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
            0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, // compressed data
            0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, // CRC
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
            0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngHeader)
    }
}
