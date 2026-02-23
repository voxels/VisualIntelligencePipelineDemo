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
    
    // MARK: - iOS/iPadOS (ARView with camera passthrough)
    
    #if !os(visionOS)
    private var iOSContent: some View {
        ZStack {
            // ARView with live camera feed
            ARCameraView(detector: detector)
                .ignoresSafeArea()
            
            // Score cards floating at bottom
            VStack {
                Spacer()
                
                if detector.detectedProducts.isEmpty {
                    // Scanning indicator
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Point at products to scan…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 100)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(detector.detectedProducts) { product in
                                ProductScoreAttachment(
                                    productName: product.productName,
                                    brand: product.brand,
                                    compositeScore: product.compositeScore,
                                    strategyScores: product.strategyScores,
                                    recommendation: product.recommendation,
                                    summary: product.summary
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 80)
                }
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
                        brand: product.brand,
                        compositeScore: product.compositeScore,
                        strategyScores: product.strategyScores,
                        recommendation: product.recommendation,
                        summary: product.summary
                    )
                }
            }
        }
    }
    #endif
}

// MARK: - ARView UIViewRepresentable (iOS Camera Passthrough)

#if !os(visionOS)
import ARKit
import Vision

/// Wraps RealityKit's ARView for live camera passthrough on iOS,
/// with barcode detection via ARSessionDelegate frame callbacks.
struct ARCameraView: UIViewRepresentable {
    let detector: SpatialProductDetector
    
    func makeCoordinator() -> Coordinator {
        Coordinator(detector: detector)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .ar
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        
        // World tracking for camera passthrough
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        arView.session.delegate = context.coordinator
        arView.session.run(config)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }
    
    // MARK: - Coordinator (ARSessionDelegate)
    
    class Coordinator: NSObject, ARSessionDelegate {
        let detector: SpatialProductDetector
        private var lastAnalysisTime: CFTimeInterval = 0
        private let analysisInterval: CFTimeInterval = 0.5 // 2 fps for barcode scanning
        private var seenBarcodes: Set<String> = []
        
        init(detector: SpatialProductDetector) {
            self.detector = detector
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let now = CACurrentMediaTime()
            guard now - lastAnalysisTime >= analysisInterval else { return }
            lastAnalysisTime = now
            
            let pixelBuffer = frame.capturedImage
            
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                
                let request = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                
                do {
                    try handler.perform([request])
                    
                    guard let results = request.results, !results.isEmpty else { return }
                    
                    for observation in results {
                        guard let payload = observation.payloadStringValue,
                              !payload.isEmpty,
                              observation.confidence > 0.8 else { continue }
                        
                        if !self.seenBarcodes.contains(payload) {
                            self.seenBarcodes.insert(payload)
                            
                            print("🛒 SpatialDetector (AR): Barcode detected: \(payload) (confidence: \(observation.confidence))")
                            
                            // Convert normalized barcode position to 3D space estimate
                            let center = observation.boundingBox
                            let x = Float(center.midX - 0.5) * 2.0
                            let y = Float(center.midY - 0.5) * 2.0
                            
                            await MainActor.run {
                                let product = SpatialDetectedProduct(
                                    anchorID: UUID(),
                                    position: SIMD3<Float>(x, y, -1),
                                    classification: "barcode",
                                    productName: payload,
                                    barcode: payload
                                )
                                self.detector.detectedProducts.append(product)
                                
                                let index = self.detector.detectedProducts.count - 1
                                Task {
                                    await self.detector.scoreProduct(at: index)
                                }
                            }
                        }
                    }
                } catch {
                    // Vision barcode detection failed — skip this frame
                }
            }
        }
    }
}
#endif
