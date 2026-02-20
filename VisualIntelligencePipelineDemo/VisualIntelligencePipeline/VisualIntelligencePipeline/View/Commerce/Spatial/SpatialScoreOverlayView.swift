//
//  SpatialScoreOverlayView.swift
//  VisualIntelligencePipeline
//
//  RealityKit view that places product score card attachments at detected
//  scene anchors. On visionOS, uses RealityView attachments API.
//  On iOS/iPadOS, uses a RealityView with SwiftUI overlay cards.
//

import SwiftUI
import RealityKit

/// Spatial AR view that overlays product score cards on detected objects.
struct SpatialScoreOverlayView: View {
    @State private var detector = SpatialProductDetector()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            #if os(visionOS)
            visionOSContent
            #else
            iOSContent
            #endif
            
            // Controls overlay (shared)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        detector.stopTracking()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                
                Spacer()
                
                if !detector.detectedProducts.isEmpty {
                    HStack {
                        Image(systemName: "cube.transparent")
                            .foregroundStyle(.green)
                        Text("\(detector.detectedProducts.count) products detected")
                            .font(.headline)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                }
            }
        }
        .task {
            do {
                try await detector.startTracking()
            } catch {
                print("⚠️ SpatialScore: Failed to start tracking: \(error)")
            }
        }
        .onDisappear {
            detector.stopTracking()
        }
    }
    
    // MARK: - iOS/iPadOS (RealityView + SwiftUI overlay)
    
    #if !os(visionOS)
    private var iOSContent: some View {
        ZStack {
            RealityView { content in
                let root = Entity()
                content.add(root)
            }
            
            // Score cards as SwiftUI overlay
            VStack {
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(detector.detectedProducts) { product in
                            ProductScoreAttachment(
                                productName: product.productName,
                                compositeScore: product.compositeScore,
                                strategyScores: product.strategyScores,
                                recommendation: product.recommendation
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 80)
            }
        }
    }
    #endif
    
    // MARK: - visionOS (RealityView with Attachments)
    
    #if os(visionOS)
    private var visionOSContent: some View {
        RealityView { content, attachments in
            let root = Entity()
            content.add(root)
            
            let light = PointLight()
            light.light.intensity = 1000
            light.position = [0, 2, 0]
            root.addChild(light)
            
        } update: { content, attachments in
            for product in detector.detectedProducts {
                if let attachment = attachments.entity(for: product.id) {
                    attachment.position = product.position + SIMD3(0, 0.3, 0)
                    attachment.components.set(BillboardComponent())
                    if attachment.parent == nil {
                        content.add(attachment)
                    }
                }
            }
        } attachments: {
            ForEach(detector.detectedProducts) { product in
                Attachment(id: product.id) {
                    ProductScoreAttachment(
                        productName: product.productName,
                        compositeScore: product.compositeScore,
                        strategyScores: product.strategyScores,
                        recommendation: product.recommendation
                    )
                }
            }
        }
    }
    #endif
}
