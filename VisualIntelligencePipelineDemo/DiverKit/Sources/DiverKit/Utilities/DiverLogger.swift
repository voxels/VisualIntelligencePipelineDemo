import Foundation
import OSLog

/// Centralized logging infrastructure for DiverKit
public enum DiverLogger {
    /// Subsystem identifier for all Diver logs
    public static let subsystem = "com.secretatomics.Diver"

    /// Logger for pipeline operations (metadata processing, enrichment)
    public static let pipeline = Logger(subsystem: subsystem, category: "pipeline")

    /// Logger for queue operations (enqueue, dequeue, processing)
    public static let queue = Logger(subsystem: subsystem, category: "queue")

    /// Logger for storage operations (SwiftData, file I/O)
    public static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Logger for network operations (API calls, SSE streams)
    public static let network = Logger(subsystem: subsystem, category: "network")

    /// Logger for authentication and security operations
    public static let auth = Logger(subsystem: subsystem, category: "auth")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log an error with context
    public func logError(_ error: Error, context: String? = nil) {
        if let context = context {
            self.error("\(context): \(error.localizedDescription)")
        } else {
            self.error("\(error.localizedDescription)")
        }
    }

    /// Log a debug message with data
    public func debug(_ message: String, data: [String: Any]) {
        self.debug("\(message) - Data: \(String(describing: data))")
    }

    /// Log an info message with metadata
    public func info(_ message: String, metadata: [String: String]) {
        let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        self.info("\(message) [\(metadataString)]")
    }
}
