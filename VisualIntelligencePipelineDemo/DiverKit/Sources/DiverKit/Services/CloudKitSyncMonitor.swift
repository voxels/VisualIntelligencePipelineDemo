//
//  CloudKitSyncMonitor.swift
//  DiverKit
//
//  Monitors CloudKit sync events from NSPersistentCloudKitContainer.
//  Logs sync outcomes, tracks last successful sync, and surfaces
//  critical failures via Notification.
//

import Foundation
import CoreData
import os.log

/// Monitors CloudKit sync health and logs events.
///
/// Thread safety: observer callback runs on `queue: .main` so all
/// mutable state updates occur on the main thread. The class is
/// `@MainActor` to enforce this at compile time.
@MainActor
public final class CloudKitSyncMonitor: ObservableObject {
    
    /// Posted when a CloudKit sync error occurs.
    /// `userInfo` contains `"error"` (Error) and `"eventType"` (String).
    public static nonisolated let syncErrorNotification = Notification.Name("CloudKitSyncError")
    
    /// Posted when sync completes successfully.
    public static nonisolated let syncSuccessNotification = Notification.Name("CloudKitSyncSuccess")
    
    private nonisolated let logger = Logger(subsystem: "com.secretatomics.VisualIntelligence", category: "CloudKitSync")
    
    /// Last successful sync timestamp.
    public private(set) var lastSuccessfulSync: Date?
    
    /// Whether a sync error is currently active.
    public private(set) var hasActiveError: Bool = false
    
    /// The most recent sync error description, if any.
    public private(set) var lastErrorDescription: String?
    
    /// Notification observer token.
    private var observer: (any NSObjectProtocol)?
    
    public init() {}
    
    /// Start monitoring CloudKit sync events.
    /// Call once after ModelContainer is created.
    public func start(for container: NSPersistentContainer? = nil) {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification"),
            object: container,
            queue: nil
        ) { [weak self] notification in
            // Extract Sendable values from the notification *before*
            // crossing the MainActor isolation boundary.
            let event: NSObject? = {
                if let e = notification.userInfo?["event"] as? NSObject { return e }
                let key = "NSPersistentCloudKitContainer.eventNotificationUserInfoKey"
                return notification.userInfo?[key] as? NSObject
            }()
            guard let event else { return }
            let succeeded = (event.value(forKey: "succeeded") as? Bool) ?? false
            let errorDesc = (event.value(forKey: "error") as? Error)?.localizedDescription
            let eventTypeRaw = (event.value(forKey: "type") as? Int) ?? -1
            
            Task { @MainActor in
                self?.processEvent(succeeded: succeeded, errorDescription: errorDesc, eventTypeRaw: eventTypeRaw)
            }
        }
        
        logger.info("CloudKit sync monitoring started")
    }
    
    /// Stop monitoring.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
    
    // MARK: - Event Handling
    
    private func processEvent(succeeded: Bool, errorDescription: String?, eventTypeRaw: Int) {
        let eventTypeName: String
        switch eventTypeRaw {
        case 0: eventTypeName = "setup"
        case 1: eventTypeName = "import"
        case 2: eventTypeName = "export"
        default: eventTypeName = "unknown(\(eventTypeRaw))"
        }
        
        if succeeded {
            lastSuccessfulSync = Date()
            hasActiveError = false
            lastErrorDescription = nil
            logger.info("☁️ CloudKit \(eventTypeName) succeeded")
            
            NotificationCenter.default.post(
                name: Self.syncSuccessNotification,
                object: nil,
                userInfo: ["eventType": eventTypeName, "date": Date()]
            )
        } else if let errorDescription {
            hasActiveError = true
            lastErrorDescription = errorDescription
            logger.error("☁️ CloudKit \(eventTypeName) failed: \(errorDescription)")
            
            NotificationCenter.default.post(
                name: Self.syncErrorNotification,
                object: nil,
                userInfo: ["errorDescription": errorDescription, "eventType": eventTypeName]
            )
        }
    }
    
    /// Human-readable sync status for UI display.
    public var statusDescription: String {
        if hasActiveError, let desc = lastErrorDescription {
            return "Sync error: \(desc)"
        }
        if let last = lastSuccessfulSync {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "Waiting for sync…"
    }
}
