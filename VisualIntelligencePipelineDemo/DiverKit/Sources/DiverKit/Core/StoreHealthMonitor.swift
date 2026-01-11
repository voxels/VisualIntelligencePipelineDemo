import Foundation
import SwiftData
import OSLog

public struct StoreHealthSnapshot: Sendable {
    public let date: Date
    public let localInputCount: Int
    public let userConceptCount: Int
    public let storeFileSizeBytes: Int64?
    
    public init(date: Date, localInputCount: Int, userConceptCount: Int, storeFileSizeBytes: Int64?) {
        self.date = date
        self.localInputCount = localInputCount
        self.userConceptCount = userConceptCount
        self.storeFileSizeBytes = storeFileSizeBytes
    }
}

public final class StoreHealthMonitor: Sendable {
    public static let shared = StoreHealthMonitor()
    private let logger = Logger(subsystem: "com.secretatomics.diverkit", category: "StoreHealthMonitor")
    
    private init() {}
    
    @MainActor
    public func captureSnapshot(label: String? = nil) -> StoreHealthSnapshot {
        guard let manager = UnifiedDataManager.shared else {
             logger.error("StoreHealthMonitor: UnifiedDataManager not initialized")
             return StoreHealthSnapshot(date: Date(), localInputCount: 0, userConceptCount: 0, storeFileSizeBytes: 0)
        }
        let context = manager.mainContext
        let inputCount = (try? context.fetchCount(FetchDescriptor<LocalInput>())) ?? 0
        let conceptCount = (try? context.fetchCount(FetchDescriptor<UserConcept>())) ?? 0
        let fileSize = currentStoreSize()
        
        let snapshot = StoreHealthSnapshot(
            date: Date(),
            localInputCount: inputCount,
            userConceptCount: conceptCount,
            storeFileSizeBytes: fileSize
        )
        
        if let label {
            log(snapshot, label: label)
        }
        
        return snapshot
    }
    
    private func currentStoreSize() -> Int64? {
        let appGroupIdentifier = "group.com.secretatomics.VisualIntelligen.shared"
        guard let storeURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Diver.sqlite") else {
            return nil
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            return attributes[.size] as? Int64
        } catch {
            logger.error("StoreHealthMonitor: failed to read store size \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    private func log(_ snapshot: StoreHealthSnapshot, label: String) {
        if let size = snapshot.storeFileSizeBytes {
            logger.info("[\(label, privacy: .public)] inputs=\(snapshot.localInputCount) concepts=\(snapshot.userConceptCount) size=\(size) bytes")
        } else {
            logger.info("[\(label, privacy: .public)] inputs=\(snapshot.localInputCount) concepts=\(snapshot.userConceptCount)")
        }
    }
}
