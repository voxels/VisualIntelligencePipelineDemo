//
//  ImmersiveScoreView.swift
//  SpatialCommerce
//
//  Full immersive RealityKit view for detailed product comparison
//  in spatial computing. Score cards attach to detected scene anchors.
//

import SwiftUI
import RealityKit

/// Immersive space view for product score overlays.
struct ImmersiveScoreView: View {
    @State private var detector = SpatialProductDetector()
    
    var body: some View {
        RealityView { content, attachments in
            // Add a root entity
            let root = Entity()
            content.add(root)
            
            // Ambient light for score cards
            let light = PointLight()
            light.light.intensity = 1000
            light.position = [0, 2, 0]
            root.addChild(light)
            
        } update: { content, attachments in
            // Place score card attachments at detected anchor positions
            for (id, anchor) in detector.detectedAnchors {
                if let attachment = attachments.entity(for: id) {
                    attachment.position = anchor.position + SIMD3(0, 0.3, 0) // Float above object
                    
                    // Billboard — face the user
                    attachment.components.set(BillboardComponent())
                    
                    if attachment.parent == nil {
                        content.add(attachment)
                    }
                }
            }
        } attachments: {
            // Create score card attachments for each detected anchor
            ForEach(Array(detector.detectedAnchors.values)) { anchor in
                Attachment(id: anchor.id) {
                    ProductScoreAttachment(
                        productName: "Detected Object",
                        compositeScore: 0.75,
                        strategyScores: [
                            ("Ethics", 0.82),
                            ("Value", 0.68),
                            ("Health", 0.71),
                        ],
                        recommendation: "Analyzing…"
                    )
                }
            }
        }
        .task {
            do {
                try await detector.startTracking()
            } catch {
                print("⚠️ ImmersiveScore: Failed to start tracking: \(error)")
            }
        }
        .onDisappear {
            detector.stopTracking()
        }
    }
}
