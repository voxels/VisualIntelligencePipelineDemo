//
//  SpatialProductDetector.swift
//  SpatialCommerce
//
//  Uses ARKit scene understanding and object detection to identify
//  products in the user's environment and trigger score overlays.
//

import Foundation
import ARKit
import RealityKit

/// Detects products in the spatial environment using ARKit.
@Observable
final class SpatialProductDetector {
    
    var detectedAnchors: [UUID: DetectedAnchor] = [:]
    var isTracking = false
    
    private let session = ARKitSession()
    
    /// Detected anchor with position and classification.
    struct DetectedAnchor: Identifiable {
        let id: UUID
        let classification: String
        let position: SIMD3<Float>
        let timestamp: Date
    }
    
    /// Start ARKit scene understanding.
    func startTracking() async throws {
        guard SceneReconstructionProvider.isSupported else {
            print("⚠️ SpatialDetector: Scene reconstruction not supported")
            return
        }
        
        let sceneReconstruction = SceneReconstructionProvider()
        
        try await session.run([sceneReconstruction])
        isTracking = true
        
        print("📷 SpatialDetector: Started ARKit scene tracking")
        
        // Process scene updates
        for await update in sceneReconstruction.anchorUpdates {
            switch update.event {
            case .added:
                let anchor = update.anchor
                let detected = DetectedAnchor(
                    id: anchor.id,
                    classification: classificationString(anchor),
                    position: anchor.originFromAnchorTransform.columns.3.xyz,
                    timestamp: .now
                )
                detectedAnchors[anchor.id] = detected
                
            case .updated:
                if var existing = detectedAnchors[update.anchor.id] {
                    existing = DetectedAnchor(
                        id: existing.id,
                        classification: classificationString(update.anchor),
                        position: update.anchor.originFromAnchorTransform.columns.3.xyz,
                        timestamp: .now
                    )
                    detectedAnchors[update.anchor.id] = existing
                }
                
            case .removed:
                detectedAnchors.removeValue(forKey: update.anchor.id)
            }
        }
    }
    
    func stopTracking() {
        session.stop()
        isTracking = false
        detectedAnchors.removeAll()
        print("📷 SpatialDetector: Stopped tracking")
    }
    
    private func classificationString(_ anchor: SceneReconstructionProvider.Anchor) -> String {
        // Scene reconstruction provides mesh data;
        // classification comes from the mesh's semantic labels
        return "object"
    }
}

// MARK: - SIMD Extension

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
