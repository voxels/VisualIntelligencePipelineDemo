import Foundation
import CoreLocation

/// Dynamic session clustering based on statistical distribution of timestamps and locations.
/// Groups items within 1 standard deviation of the mean.
public struct SessionClusteringService {
    
    /// Minimum cluster size - smaller clusters will be merged with nearest neighbor
    private let minClusterSize = 1
    
    public init() {}
    
    /// Cluster imported assets into sessions based on time and location similarity.
    /// Uses 1σ (standard deviation) of the distribution for grouping thresholds.
    /// - Parameter items: Array of imported assets with metadata
    /// - Returns: Array of clusters, each becoming a DiverSession
    public func clusterItems(_ items: [ImportedAsset]) -> [[ImportedAsset]] {
        guard !items.isEmpty else { return [] }
        
        // Sort by creation date
        let sorted = items.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        
        // Calculate thresholds from distribution
        let (timeThreshold, distanceThreshold) = calculateThresholds(from: sorted)
        
        print("📊 Clustering: Time threshold = \(timeThreshold/3600)h, Distance threshold = \(distanceThreshold)m")
        
        var clusters: [[ImportedAsset]] = []
        var currentCluster: [ImportedAsset] = []
        
        for item in sorted {
            if currentCluster.isEmpty {
                currentCluster.append(item)
            } else {
                let lastItem = currentCluster.last!
                
                let timeDiff = abs((item.creationDate ?? .distantPast).timeIntervalSince(lastItem.creationDate ?? .distantPast))
                let distance = calculateDistance(from: lastItem.location, to: item.location)
                
                // Content similarity factor: same content type gets a clustering bonus
                let sameContentType = contentTypeSimilarity(a: lastItem, b: item)
                
                // LOCATION is primary criterion - different locations ALWAYS create new session
                // Time is secondary - long time gaps also create new sessions
                // Content type similarity allows slightly more tolerance for borderline cases
                let effectiveTimeThreshold = sameContentType ? timeThreshold * 1.2 : timeThreshold
                let effectiveDistanceThreshold = sameContentType ? distanceThreshold * 1.1 : distanceThreshold
                
                let locationChanged = distance > effectiveDistanceThreshold && distance > 100 // At least 100m difference
                let timeGapExceeded = timeDiff > effectiveTimeThreshold
                
                if locationChanged || timeGapExceeded {
                    // Start new cluster
                    clusters.append(currentCluster)
                    currentCluster = [item]
                    
                    if locationChanged {
                        print("📍 New session: Location changed by \(Int(distance))m")
                    } else {
                        print("⏱️ New session: Time gap of \(Int(timeDiff/3600))h")
                    }
                } else {
                    currentCluster.append(item)
                }
            }
        }
        
        // Don't forget the last cluster
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }
        
        print("📊 Clustering: Created \(clusters.count) clusters from \(items.count) items")
        
        return clusters
    }
    
    /// Check content type similarity between two assets
    private func contentTypeSimilarity(a: ImportedAsset, b: ImportedAsset) -> Bool {
        // Same video/photo type
        if a.isVideo == b.isVideo { return true }
        // Both screenshots
        if a.isScreenshot && b.isScreenshot { return true }
        // Both screen recordings
        if a.isScreenRecording && b.isScreenRecording { return true }
        return false
    }
    
    // MARK: - Private Helpers
    
    /// Calculate thresholds based on 1 standard deviation of the distribution
    private func calculateThresholds(from items: [ImportedAsset]) -> (timeThreshold: TimeInterval, distanceThreshold: Double) {
        // Time intervals between consecutive items
        var timeIntervals: [TimeInterval] = []
        var distances: [Double] = []
        
        for i in 1..<items.count {
            let prev = items[i-1]
            let curr = items[i]
            
            if let prevDate = prev.creationDate, let currDate = curr.creationDate {
                timeIntervals.append(abs(currDate.timeIntervalSince(prevDate)))
            }
            
            let dist = calculateDistance(from: prev.location, to: curr.location)
            if dist > 0 {
                distances.append(dist)
            }
        }
        
        // Calculate time threshold (mean + 1σ)
        let timeThreshold: TimeInterval
        if timeIntervals.isEmpty {
            timeThreshold = 4 * 3600 // Default 4 hours
        } else {
            let meanTime = timeIntervals.reduce(0, +) / Double(timeIntervals.count)
            let varianceTime = timeIntervals.map { pow($0 - meanTime, 2) }.reduce(0, +) / Double(timeIntervals.count)
            let stdDevTime = sqrt(varianceTime)
            timeThreshold = max(meanTime + stdDevTime, 3600) // At least 1 hour
        }
        
        // Calculate distance threshold (mean + 1σ)
        let distanceThreshold: Double
        if distances.isEmpty || distances.allSatisfy({ $0 == 0 }) {
            distanceThreshold = 500 // Default 500 meters
        } else {
            let validDistances = distances.filter { $0 > 0 }
            let meanDist = validDistances.reduce(0, +) / Double(validDistances.count)
            let varianceDist = validDistances.map { pow($0 - meanDist, 2) }.reduce(0, +) / Double(validDistances.count)
            let stdDevDist = sqrt(varianceDist)
            distanceThreshold = max(meanDist + stdDevDist, 100) // At least 100 meters
        }
        
        return (timeThreshold, distanceThreshold)
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D?, to: CLLocationCoordinate2D?) -> Double {
        guard let from = from, let to = to else { return 0 }
        
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        
        return fromLocation.distance(from: toLocation)
    }
    
    /// Generate session metadata from a cluster
    /// Uses the FIRST photo's timestamp and location to set session context
    public func generateSessionMetadata(from cluster: [ImportedAsset], collectionID: String?) -> (sessionID: String, timestamp: Date, location: CLLocationCoordinate2D?) {
        let sessionID = UUID().uuidString
        
        // Sort cluster by date and use FIRST photo's metadata
        let sortedCluster = cluster.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        let firstItem = sortedCluster.first
        
        // Use the FIRST photo's timestamp (earliest in session)
        let timestamp = firstItem?.creationDate ?? Date()
        
        // Use the FIRST photo's location (defines the session's place)
        let location = firstItem?.location
        
        return (sessionID, timestamp, location)
    }
}
