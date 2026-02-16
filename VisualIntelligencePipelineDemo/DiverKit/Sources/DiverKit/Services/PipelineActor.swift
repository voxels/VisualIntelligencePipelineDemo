import Foundation

/// Dedicated global actor for pipeline processing.
/// All `LocalPipelineService` work runs on this actor's serial executor,
/// keeping it off the main thread while providing isolation guarantees.
@globalActor
public actor PipelineActor {
    public static let shared = PipelineActor()
}
