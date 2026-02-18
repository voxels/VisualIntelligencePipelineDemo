//
//  QueueProgressEvent.swift
//  DiverKit
//
//  Value-type event emitted by MetadataPipelineService via AsyncStream.
//  Replaces direct observation of mutable progress properties.
//

import Foundation

/// Describes a single progress update from the metadata processing queue.
public enum QueueProgressEvent: Sendable {
    /// Queue processing has started with the given total item count.
    case started(totalCount: Int)
    
    /// An individual item is now being processed.
    case processingItem(
        completedCount: Int,
        totalCount: Int,
        itemTitle: String?,
        statusMessage: String?
    )
    
    /// An individual item completed processing.
    case itemCompleted(
        completedCount: Int,
        totalCount: Int
    )
    
    /// All items in the queue have been processed.
    case completed(totalCount: Int)
    
    /// Processing was cancelled (e.g. app backgrounded).
    case cancelled
}

extension QueueProgressEvent {
    /// Convenience: fraction complete (0.0–1.0).
    public var progress: Double {
        switch self {
        case .started:
            return 0
        case .processingItem(let completed, let total, _, _),
             .itemCompleted(let completed, let total):
            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        case .completed:
            return 1.0
        case .cancelled:
            return 0
        }
    }
    
    /// Whether processing is actively running.
    public var isProcessing: Bool {
        switch self {
        case .started, .processingItem, .itemCompleted:
            return true
        case .completed, .cancelled:
            return false
        }
    }
}
