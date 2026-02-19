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
    func unloadModel()
    func ensureModelAvailable(progress: @escaping @Sendable (Double) -> Void) async throws
    func deleteModel() throws
    func analyze(
        image: CGImage?,
        visionTags: [String],
        enrichmentContext: String,
        transcription: String?
    ) async throws -> FastVLMAnalysis?
}

// MARK: - EdgeNodeDiscovering

/// Protocol for discovering and managing edge node connections on the local network.
/// Implementations use Bonjour (NWBrowser/NWListener) to find available M-series
/// Mac or iPad edge nodes for ML offloading.
public protocol EdgeNodeDiscovering: Sendable {
    /// Currently discovered edge nodes on the local network.
    var availableNodes: [EdgeNodeInfo] { get async }
    
    /// The currently connected edge node, if any.
    var connectedNode: EdgeNodeInfo? { get async }
    
    /// Whether an edge node is currently connected and available for inference.
    var isEdgeNodeConnected: Bool { get async }
    
    /// Start scanning for edge nodes via Bonjour.
    func startDiscovery() async
    
    /// Stop scanning.
    func stopDiscovery() async
    
    /// Connect to a specific edge node.
    func connect(to node: EdgeNodeInfo) async throws
    
    /// Disconnect from the current edge node.
    func disconnect() async
}

// MARK: - CommerceRouting

/// Protocol for routing product purchases through affiliate deep links.
/// Implementations resolve a product to platform-specific purchase URLs
/// with affiliate tracking and ethical filtering.
public protocol CommerceRouting: Sendable {
    /// Generate an affiliate deep link for a product on a specific platform.
    /// - Parameters:
    ///   - product: The classified product to route
    ///   - platform: Target commerce platform (e.g., "amazon", "target", "bestbuy")
    /// - Returns: A deep link URL with affiliate tracking, or nil if unavailable
    func affiliateLink(for product: ProductClassification, platform: String) async throws -> URL?
    
    /// Rank available platforms for a product by ethical match score.
    /// - Parameters:
    ///   - product: The classified product
    ///   - policy: User's ethical filtering preferences
    /// - Returns: Platforms sorted best-first with match scores
    func rankPlatforms(for product: ProductClassification, policy: EthicalPolicy) async throws -> [PlatformMatch]
}

// MARK: - PriceNowcasting

/// Protocol for economic trend projection using Dynamic Factor Models.
/// Implementations use Accelerate (BLAS/LAPACK, vDSP) for computation.
public protocol PriceNowcasting: Sendable {
    /// Generate a price trajectory projection for a commodity.
    /// - Parameters:
    ///   - commodityID: Identifier for the commodity/product category
    ///   - horizonDays: Number of days to project forward (default: 14)
    /// - Returns: Price trajectory with data points and projected direction
    func project(commodityID: String, horizonDays: Int) async throws -> PriceTrajectory
}

