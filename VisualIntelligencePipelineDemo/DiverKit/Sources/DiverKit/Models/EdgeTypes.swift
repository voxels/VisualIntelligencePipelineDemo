//
//  EdgeTypes.swift
//  DiverKit
//
//  Codable types for distributed actor communication between
//  iOS/iPadOS clients and M-series Mac/iPad edge nodes.
//

import Foundation
import DiverShared

// MARK: - Edge Node Discovery

/// Information about an available edge node on the local network.
public struct EdgeNodeInfo: Codable, Sendable, Hashable {
    public let deviceName: String       // e.g., "Michael's MacBook Pro"
    public let chipFamily: String       // e.g., "M4 Pro"
    public let neuralEngineTOPS: Float  // e.g., 38.0
    public let physicalMemoryGB: UInt64 // e.g., 32
    public let availableModels: [String] // e.g., ["FastVLM-0.5B", "FastVLM-3B", "YOLO-v8n"]
    public var isAvailable: Bool
    
    public init(
        deviceName: String,
        chipFamily: String,
        neuralEngineTOPS: Float,
        physicalMemoryGB: UInt64,
        availableModels: [String],
        isAvailable: Bool = true
    ) {
        self.deviceName = deviceName
        self.chipFamily = chipFamily
        self.neuralEngineTOPS = neuralEngineTOPS
        self.physicalMemoryGB = physicalMemoryGB
        self.availableModels = availableModels
        self.isAvailable = isAvailable
    }
}

// MARK: - Inference Results

/// Result of a Vision analysis performed on an edge node.
/// Encapsulates all results that would normally come from IntelligenceProcessor.
public struct VisionAnalysisResult: Codable, Sendable {
    public let ocrText: String?
    public let qrURLs: [String]
    public let semanticTags: [String]
    public let hasDocument: Bool
    public let hasForegroundSubject: Bool
    public let aestheticsScore: Float?
    public let saliencyMap: SaliencyResult?
    
    public init(
        ocrText: String? = nil,
        qrURLs: [String] = [],
        semanticTags: [String] = [],
        hasDocument: Bool = false,
        hasForegroundSubject: Bool = false,
        aestheticsScore: Float? = nil,
        saliencyMap: SaliencyResult? = nil
    ) {
        self.ocrText = ocrText
        self.qrURLs = qrURLs
        self.semanticTags = semanticTags
        self.hasDocument = hasDocument
        self.hasForegroundSubject = hasForegroundSubject
        self.aestheticsScore = aestheticsScore
        self.saliencyMap = saliencyMap
    }
}

/// Saliency map result — attention-based or objectness-based.
public struct SaliencyResult: Codable, Sendable {
    public let width: Int
    public let height: Int
    /// Flattened row-major saliency values (0.0–1.0) for each cell in the grid.
    public let heatmap: [Float]
    /// Bounding boxes of salient regions, normalized (0–1) coordinates.
    public let salientRegions: [NormalizedRect]
    
    public init(width: Int, height: Int, heatmap: [Float], salientRegions: [NormalizedRect] = []) {
        self.width = width
        self.height = height
        self.heatmap = heatmap
        self.salientRegions = salientRegions
    }
}

/// A normalized rectangle (origin bottom-left, 0–1 coordinates).
public struct NormalizedRect: Codable, Sendable, Hashable {
    public let x: Float
    public let y: Float
    public let width: Float
    public let height: Float
    
    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Result of an LLM analysis performed on an edge node.
public struct LLMAnalysisResult: Codable, Sendable {
    public let summary: String?
    public let statements: [String]
    public let purpose: String?
    public let tags: [String]
    public let imageDescription: String?
    
    public init(
        summary: String? = nil,
        statements: [String] = [],
        purpose: String? = nil,
        tags: [String] = [],
        imageDescription: String? = nil
    ) {
        self.summary = summary
        self.statements = statements
        self.purpose = purpose
        self.tags = tags
        self.imageDescription = imageDescription
    }
}

// MARK: - Edge Node Status

/// Real-time status of an edge node for dashboard display.
public struct EdgeNodeStatus: Codable, Sendable {
    public let deviceName: String
    public let connectedClients: Int
    public let isProcessing: Bool
    public let loadedModels: [ModelStatus]
    public let inferenceRequestsPerMinute: Float
    public let uptimeSeconds: TimeInterval
    
    public init(
        deviceName: String,
        connectedClients: Int = 0,
        isProcessing: Bool = false,
        loadedModels: [ModelStatus] = [],
        inferenceRequestsPerMinute: Float = 0,
        uptimeSeconds: TimeInterval = 0
    ) {
        self.deviceName = deviceName
        self.connectedClients = connectedClients
        self.isProcessing = isProcessing
        self.loadedModels = loadedModels
        self.inferenceRequestsPerMinute = inferenceRequestsPerMinute
        self.uptimeSeconds = uptimeSeconds
    }
}

/// Status of a single ML model on the edge node.
public struct ModelStatus: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String         // e.g., "FastVLM-3B"
    public let sizeBytes: Int64
    public let state: ModelState
    public let downloadProgress: Float? // 0.0–1.0 during download
    
    public init(name: String, sizeBytes: Int64, state: ModelState, downloadProgress: Float? = nil) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.state = state
        self.downloadProgress = downloadProgress
    }
}

/// State of a model on the edge node.
public enum ModelState: String, Codable, Sendable {
    case notDownloaded
    case downloading
    case downloaded
    case loaded      // In memory, ready for inference
    case error
}

// MARK: - Agentic Search (CLaRa)

/// Payload sent from iOS client to macOS EdgeDaemon to be compressed into a latent vector by CLaRa.
public struct AgenticSearchIngestPayload: Codable, Sendable {
    public let documentID: String
    public let textContent: String
    public let metadata: [String: String]
    
    public init(documentID: String, textContent: String, metadata: [String: String] = [:]) {
        self.documentID = documentID
        self.textContent = textContent
        self.metadata = metadata
    }
}

/// A search query sent to the EdgeDaemon.
public struct AgenticSearchQuery: Codable, Sendable {
    public let queryText: String
    public let topK: Int
    /// Pre-assembled context from the client's local document index.
    /// The EdgeDaemon uses this as the document text for CLaRa inference,
    /// so the model answers based on the user's actual library content.
    public let contextPayload: String?
    
    public init(queryText: String, topK: Int = 5, contextPayload: String? = nil) {
        self.queryText = queryText
        self.topK = topK
        self.contextPayload = contextPayload
    }
}

/// The response generated by the CLaRa 7B model.
public struct AgenticSearchResult: Codable, Sendable {
    public let generatedAnswer: String
    public let citedDocumentIDs: [String]
    
    public init(generatedAnswer: String, citedDocumentIDs: [String]) {
        self.generatedAnswer = generatedAnswer
        self.citedDocumentIDs = citedDocumentIDs
    }
}

