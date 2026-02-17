import XCTest
import CoreLocation
@testable import DiverKit

final class SessionClusteringServiceTests: XCTestCase {
    
    var service: SessionClusteringService!
    
    override func setUp() {
        super.setUp()
        service = SessionClusteringService()
    }
    
    // MARK: - Empty / Single Input
    
    func testEmptyInputReturnsNoClusters() {
        let clusters = service.clusterItems([])
        XCTAssertTrue(clusters.isEmpty, "Empty input should produce no clusters")
    }
    
    func testSingleItemProducesOneCluster() {
        let item = makeImportedAsset(creationDate: Date())
        let clusters = service.clusterItems([item])
        
        XCTAssertEqual(clusters.count, 1, "Single item should produce exactly one cluster")
        XCTAssertEqual(clusters.first?.count, 1)
    }
    
    // MARK: - Time-Based Clustering
    
    func testItemsWithinShortTimeGroupTogether() {
        let now = Date()
        let items = (0..<5).map { i in
            makeImportedAsset(creationDate: now.addingTimeInterval(Double(i) * 60)) // 1 min apart
        }
        
        let clusters = service.clusterItems(items)
        
        XCTAssertEqual(clusters.count, 1, "Items 1 minute apart should cluster together")
        XCTAssertEqual(clusters.first?.count, 5)
    }
    
    func testItemsFarApartInTimeSplitIntoClusters() {
        let now = Date()
        // Group 1: 3 items within 5 minutes
        let group1 = (0..<3).map { i in
            makeImportedAsset(creationDate: now.addingTimeInterval(Double(i) * 60))
        }
        // Group 2: 3 items 24 hours later, within 5 minutes of each other
        let group2 = (0..<3).map { i in
            makeImportedAsset(creationDate: now.addingTimeInterval(24 * 3600 + Double(i) * 60))
        }
        
        let allItems = group1 + group2
        let clusters = service.clusterItems(allItems)
        
        XCTAssertEqual(clusters.count, 2, "Items 24 hours apart should split into 2 clusters")
    }
    
    // MARK: - Location-Based Clustering
    
    func testItemsAtDifferentLocationsSplitIntoClusters() {
        let now = Date()
        // NYC items - 3 items within 5 minutes
        let nycItems = (0..<3).map { i in
            makeImportedAsset(
                creationDate: now.addingTimeInterval(Double(i) * 60),
                latitude: 40.7128, longitude: -74.0060
            )
        }
        // LA items - 3 items starting 2 hours later (far in both time and location)
        // The clustering service uses dynamic thresholds (min 1h for time),
        // so we need sufficient time gap + location distance to guarantee a split.
        let laItems = (0..<3).map { i in
            makeImportedAsset(
                creationDate: now.addingTimeInterval(7200 + Double(i) * 60),
                latitude: 34.0522, longitude: -118.2437
            )
        }
        
        let allItems = nycItems + laItems
        let clusters = service.clusterItems(allItems)
        
        XCTAssertGreaterThanOrEqual(clusters.count, 2, "Items in NYC and LA should be in different clusters")
    }

    
    func testItemsAtSameLocationGroupTogether() {
        let now = Date()
        // All items at the same location, 30 min apart
        let items = (0..<5).map { i in
            makeImportedAsset(
                creationDate: now.addingTimeInterval(Double(i) * 1800), // 30 min apart
                latitude: 40.7128, longitude: -74.0060
            )
        }
        
        let clusters = service.clusterItems(items)
        
        // Items at same location within ~2 hours should cluster
        XCTAssertLessThanOrEqual(clusters.count, 2, "Items at same location within a few hours should mostly cluster")
    }
    
    // MARK: - Metadata Generation
    
    func testGenerateSessionMetadataUsesFirstItemTimestamp() {
        let earlyDate = Date(timeIntervalSince1970: 1_000_000)
        let lateDate = Date(timeIntervalSince1970: 2_000_000)
        
        let items = [
            makeImportedAsset(creationDate: lateDate),
            makeImportedAsset(creationDate: earlyDate) // Earlier, but second in array
        ]
        
        let (_, timestamp, _) = service.generateSessionMetadata(from: items, collectionID: nil)
        
        XCTAssertEqual(timestamp, earlyDate, "Should use the FIRST (earliest) item's timestamp after sorting")
    }
    
    func testGenerateSessionMetadataUsesFirstItemLocation() {
        let items = [
            makeImportedAsset(
                creationDate: Date(timeIntervalSince1970: 1_000_000),
                latitude: 40.7128, longitude: -74.0060
            ),
            makeImportedAsset(
                creationDate: Date(timeIntervalSince1970: 2_000_000),
                latitude: 34.0522, longitude: -118.2437
            )
        ]
        
        let (_, _, location) = service.generateSessionMetadata(from: items, collectionID: nil)
        
        XCTAssertNotNil(location, "Should have a location from the first item")
        XCTAssertEqual(location?.latitude ?? 0, 40.7128, accuracy: 0.001, "Should use first item's latitude")
    }
    
    func testGenerateSessionMetadataReturnsUniqueSessionID() {
        let items = [makeImportedAsset()]
        
        let (id1, _, _) = service.generateSessionMetadata(from: items, collectionID: nil)
        let (id2, _, _) = service.generateSessionMetadata(from: items, collectionID: nil)
        
        XCTAssertNotEqual(id1, id2, "Each call should generate a unique session ID")
    }
    
    // MARK: - Content Type Similarity
    
    func testSameContentTypeGetsClusteringBonus() {
        let now = Date()
        // All videos, spaced moderately apart (should get bonus tolerance)
        let videoItems = (0..<4).map { i in
            makeImportedAsset(
                creationDate: now.addingTimeInterval(Double(i) * 3600), // 1h apart
                isVideo: true
            )
        }
        
        let videoClusters = service.clusterItems(videoItems)
        
        // Mixed content (alternating), same timing
        let mixedItems = (0..<4).map { i in
            makeImportedAsset(
                creationDate: now.addingTimeInterval(Double(i) * 3600), // 1h apart
                isVideo: i % 2 == 0
            )
        }
        
        let mixedClusters = service.clusterItems(mixedItems)
        
        // Videos should cluster at least as well as mixed content
        XCTAssertLessThanOrEqual(videoClusters.count, mixedClusters.count,
                                 "Same content type should cluster at least as tightly as mixed content")
    }
    
    // MARK: - Ordering
    
    func testItemsAreClusteredInChronologicalOrder() {
        let now = Date()
        // Insert in reverse order
        let items = (0..<5).reversed().map { i in
            makeImportedAsset(creationDate: now.addingTimeInterval(Double(i) * 60))
        }
        
        let clusters = service.clusterItems(items)
        
        // Should still produce one cluster (all within 5 minutes)
        XCTAssertEqual(clusters.count, 1, "Service should sort by date, so reverse order input still clusters")
        
        // Verify items within the cluster are sorted chronologically
        if let cluster = clusters.first {
            for i in 1..<cluster.count {
                let prevDate = cluster[i-1].creationDate ?? .distantPast
                let currDate = cluster[i].creationDate ?? .distantPast
                XCTAssertLessThanOrEqual(prevDate, currDate, "Items within cluster should be chronological")
            }
        }
    }
}
