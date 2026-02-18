import Foundation
import CoreGraphics
@testable import DiverKit

/// Mock FastVLMEnrichmentService that conforms to `FastVLMAnalyzing` protocol.
/// Tracks calls for testing background cancellation, model unloading, and lifecycle management.
public final class MockFastVLMService: FastVLMAnalyzing, @unchecked Sendable {
    
    // MARK: - State Tracking
    
    /// Whether `retainModel` was set (mirrors `FastVLMEnrichmentService.retainModel`)
    public var retainModel: Bool = false
    
    /// Number of times `unloadModel()` was called
    public private(set) var unloadModelCallCount = 0
    
    /// Number of times `analyze()` was called
    public private(set) var analyzeCallCount = 0
    
    /// Whether the mock was "loaded" into GPU memory
    public private(set) var isModelLoaded = false
    
    /// Protocol conformance: availability check
    public var isAvailable: Bool = true
    
    /// Configurable result for analyze()
    public var analyzeResult: FastVLMAnalysis? = nil
    
    /// Configurable delay for analyze() (simulates inference time for cancellation testing)
    public var analyzeDelay: Duration? = nil
    
    /// Error to throw from analyze()
    public var errorToThrow: Error? = nil
    
    public init() {}
    
    // MARK: - Protocol Methods
    
    public func loadModel() async throws {
        isModelLoaded = true
    }
    
    public func ensureModelAvailable(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1.0)
    }
    
    public func deleteModel() throws {
        isModelLoaded = false
    }
    
    public func unloadModel() {
        unloadModelCallCount += 1
        isModelLoaded = false
    }
    
    public func analyze(
        image: CGImage?,
        visionTags: [String] = [],
        enrichmentContext: String,
        transcription: String? = nil
    ) async throws -> FastVLMAnalysis? {
        analyzeCallCount += 1
        if let error = errorToThrow { throw error }
        if let delay = analyzeDelay {
            try await Task.sleep(for: delay)
        }
        return analyzeResult
    }
    
    /// Resets all tracking state for reuse between tests.
    public func reset() {
        retainModel = false
        unloadModelCallCount = 0
        analyzeCallCount = 0
        isModelLoaded = false
        isAvailable = true
        analyzeResult = nil
        analyzeDelay = nil
        errorToThrow = nil
    }
}

