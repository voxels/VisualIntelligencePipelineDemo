
import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif
import DiverShared

#if os(macOS)
// Mock for macOS
public actor ActivityEnrichmentService {
    public init() {}
    public func fetchCurrentActivity() async -> ActivityContext? { return nil }
}
#else
public actor ActivityEnrichmentService {
    private let motionActivityManager = CMMotionActivityManager()
    private let operationQueue = OperationQueue()
    
    public init() {}
    
    public func fetchCurrentActivity() async -> ActivityContext? {
        // CoreMotion disabled per user request due to stability issues
        return nil
        
        /*
        guard CMMotionActivityManager.isActivityAvailable() else {
            return nil
        }
        
        let status = CMMotionActivityManager.authorizationStatus()
        switch status {
        case .denied, .restricted:
            print("Motion activity access denied or restricted")
            return nil
        case .notDetermined, .authorized:
            // Continue to query
            break
        @unknown default:
            print("Unknown motion authorization status")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let now = Date()
            motionActivityManager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: operationQueue) { activities, error in
                if let error = error {
                    print("Error querying motion activity: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Get the most recent activity with high/medium confidence
                if let recentActivity = activities?.last(where: { $0.confidence == .high || $0.confidence == .medium }) {
                    let type = ActivityEnrichmentService.activityTypeString(for: recentActivity)
                    let confidence = ActivityEnrichmentService.confidenceString(for: recentActivity.confidence)
                    continuation.resume(returning: ActivityContext(type: type, confidence: confidence))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        }
        */
    }
    
    private static func activityTypeString(for activity: CMMotionActivity) -> String {
        if activity.automotive { return "automotive" }
        if activity.cycling { return "cycling" }
        if activity.running { return "running" }
        if activity.walking { return "walking" }
        if activity.stationary { return "stationary" }
        return "unknown"
    }
    
    private static func confidenceString(for confidence: CMMotionActivityConfidence) -> String {
        switch confidence {
        case .high: return "high"
        case .medium: return "medium" // Ensure we handle medium even if we filter for it
        case .low: return "low"
        @unknown default: return "unknown"
        }
    }
}
#endif


