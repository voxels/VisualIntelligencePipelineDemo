import Foundation

/// Represents the processing status of an item in the pipeline
public enum ProcessingStatus: String, Codable, Sendable {
    /// Item is queued for processing
    case queued

    /// Item is currently being processed (Phase 1: Vision + Location)
    case processing

    /// Phase 1 complete: Vision, Location, and Web enrichment done.
    /// Item is visible in sidebar with tags, thumbnails, and location.
    /// Awaiting Phase 2 background enrichment (SLM, FastVLM, Commerce).
    case captured

    /// Phase 2 in progress: background enrichment running
    /// (CLaRa/SLM, FastVLM, Commerce, Concepts)
    case enriching

    /// Item is ready and fully processed (both phases complete)
    case ready

    /// Item processing failed
    case failed

    /// Item requires user review (e.g. place verification)
    case reviewRequired

    /// Item has been archived
    case archived
}
