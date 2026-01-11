import Foundation

/// Represents the processing status of an item in the pipeline
public enum ProcessingStatus: String, Codable, Sendable {
    /// Item is queued for processing
    case queued

    /// Item is currently being processed
    case processing

    /// Item is ready and successfully processed
    case ready

    /// Item processing failed
    case failed

    /// Item requires user review (e.g. place verification)
    case reviewRequired

    /// Item has been archived
    case archived
}
