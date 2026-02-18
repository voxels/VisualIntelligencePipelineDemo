//
//  ServiceProtocols.swift
//  DiverKit
//
//  Protocols for core pipeline services, enabling testability and dependency injection.
//  Each protocol captures the public API surface of its concrete implementation.
//

import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import DiverShared

// MARK: - IntelligenceProcessing

/// Protocol for Vision-based image analysis (OCR, QR, semantic, sifting, aesthetics).
public protocol IntelligenceProcessing: Sendable {
    func process(frame: CVPixelBuffer, orientation: CGImagePropertyOrientation, mode: IntelligenceProcessor.AnalysisMode) async throws -> [IntelligenceResult]
    func process(image: CGImage, orientation: CGImagePropertyOrientation, mode: IntelligenceProcessor.AnalysisMode) async throws -> [IntelligenceResult]
}

// MARK: - ContextProcessing

/// Protocol for on-device LLM context analysis (summaries, questions, purposes).
public protocol ContextProcessing: Sendable {
    func processContext(from data: EnrichmentData, sessionID: String?) async throws -> (summary: String?, statements: [String], purpose: String?, tags: [String])
    func summarizeText(_ text: String) async throws -> String
}

// MARK: - AestheticsScoring

/// Protocol for image/video quality scoring via Vision framework.
public protocol AestheticsScoring: Sendable {
    func extractBestFrames(from videoURL: URL, count: Int) async throws -> [Thumbnail]
    func bestThumbnailFromImage(_ cgImage: CGImage) async throws -> Thumbnail
}

// MARK: - FastVLMAnalyzing

/// Protocol for multimodal image understanding via FastVLM.
/// Note: availability checks use instance properties rather than static to enable DI.
public protocol FastVLMAnalyzing: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var isModelLoaded: Bool { get }
    var retainModel: Bool { get set }
    
    func loadModel() async throws
    func ensureModelAvailable(progress: @escaping @Sendable (Double) -> Void) async throws
    func deleteModel() throws
    func analyze(
        image: CGImage?,
        visionTags: [String],
        enrichmentContext: String,
        transcription: String?
    ) async throws -> FastVLMAnalysis?
}
