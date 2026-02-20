//
//  SpatialProductDetector.swift
//  VisualIntelligencePipeline
//
//  Uses ARKit scene understanding to detect products in the environment
//  and feeds them through the pipeline's scoring engines.
//  ARKitSession + SceneReconstructionProvider require visionOS.
//  On iOS/iPadOS, detection uses camera-based Vision framework instead.
//

import Foundation
import SwiftUI
import RealityKit

#if os(visionOS)
import ARKit
#endif

/// Detects products in the spatial environment.
/// On visionOS: uses ARKitSession + SceneReconstructionProvider for spatial detection.
/// On iOS/iPadOS: detection is handled by the existing Vision pipeline (camera-based).
@Observable
final class SpatialProductDetector {
    
    var detectedProducts: [SpatialDetectedProduct] = []
    var isTracking = false
    
    #if os(visionOS)
    private let session = ARKitSession()
    
    /// Start ARKit scene understanding for spatial product detection.
    func startTracking() async throws {
        guard SceneReconstructionProvider.isSupported else {
            print("⚠️ SpatialDetector: Scene reconstruction not supported on this device")
            return
        }
        
        let sceneReconstruction = SceneReconstructionProvider()
        try await session.run([sceneReconstruction])
        isTracking = true
        
        print("📷 SpatialDetector: Started ARKit scene tracking")
        
        for await update in sceneReconstruction.anchorUpdates {
            switch update.event {
            case .added:
                let anchor = update.anchor
                let product = SpatialDetectedProduct(
                    anchorID: anchor.id,
                    position: anchor.originFromAnchorTransform.columns.3.xyz,
                    classification: "object"
                )
                detectedProducts.append(product)
                
            case .updated:
                if let index = detectedProducts.firstIndex(where: { $0.anchorID == update.anchor.id }) {
                    detectedProducts[index].position = update.anchor.originFromAnchorTransform.columns.3.xyz
                }
                
            case .removed:
                detectedProducts.removeAll { $0.anchorID == update.anchor.id }
            }
        }
    }
    
    func stopTracking() {
        session.stop()
        isTracking = false
        detectedProducts.removeAll()
        print("📷 SpatialDetector: Stopped tracking")
    }
    #else
    /// On iOS/iPadOS, spatial detection is handled by the camera pipeline.
    /// This is a no-op — the existing VisualIntelligenceViewModel handles
    /// product detection via Vision framework barcode/classification.
    func startTracking() async throws {
        print("ℹ️ SpatialDetector: Using camera-based detection on iOS")
        isTracking = true
    }
    
    func stopTracking() {
        isTracking = false
        detectedProducts.removeAll()
    }
    #endif
}

/// A product detected in the spatial environment.
struct SpatialDetectedProduct: Identifiable {
    let id = UUID()
    let anchorID: UUID
    var position: SIMD3<Float>
    let classification: String
    let timestamp: Date = .now
    
    /// Pipeline-generated scores (populated after scoring).
    var productName: String = "Detected Object"
    var compositeScore: Float = 0.0
    var strategyScores: [(name: String, score: Float)] = []
    var recommendation: String = "Analyzing…"
    
    var scoreColor: Color {
        if compositeScore >= 0.7 { return .green }
        if compositeScore >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - SIMD Extension

#if os(visionOS)
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
#endif
