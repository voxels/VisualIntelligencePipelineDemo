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
    
    // MARK: - iOS/iPadOS (ARView with world-anchored cards)
    
    #if !os(visionOS)
    private var iOSContent: some View {
        ZStack {
            // ARView with live camera feed + barcode detection
            ARCameraView(detector: detector)
                .ignoresSafeArea()
            
            // World-anchored score cards — positioned at projected barcode locations
            let productsWithData = detector.detectedProducts.filter { $0.hasData }
            let stillScoring = detector.detectedProducts.contains { $0.isScoring }
            
            ForEach(productsWithData) { product in
                ProductScoreAttachment(
                    productName: product.productName,
                    brand: product.brand,
                    compositeScore: product.compositeScore,
                    strategyScores: product.strategyScores,
                    recommendation: product.recommendation,
                    summary: product.summary
                )
                .scaleEffect(0.85)
                .position(
                    x: CGFloat(product.screenPosition.x),
                    y: CGFloat(product.screenPosition.y)
                )
                .opacity(product.screenPosition.z > 0 ? 1 : 0) // Hide if behind camera
                .animation(.easeInOut(duration: 0.15), value: product.screenPosition.x)
                .animation(.easeInOut(duration: 0.15), value: product.screenPosition.y)
            }
            
            // Scanning indicator (only when no results at all)
            if productsWithData.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text(stillScoring ? "Identifying product…" : "Point at products to scan…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 100)
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
            ForEach(detector.detectedProducts.filter { $0.hasData }) { product in
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

// MARK: - ARView UIViewRepresentable (iOS World-Anchored)

#if !os(visionOS)
import ARKit
import Vision

/// Wraps RealityKit's ARView for live camera passthrough on iOS.
/// Detects barcodes via Vision, anchors them in world space,
/// and projects their positions to screen coordinates each frame
/// so SwiftUI cards track the physical product.
struct ARCameraView: UIViewRepresentable {
    let detector: SpatialProductDetector
    
    func makeCoordinator() -> Coordinator {
        Coordinator(detector: detector)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .ar
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        
        // World tracking with plane detection for depth estimation
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        context.coordinator.arView = arView
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
        weak var arView: ARView?
        private var lastAnalysisTime: CFTimeInterval = 0
        private let analysisInterval: CFTimeInterval = 0.5 // 2 fps for barcode scanning
        private var seenBarcodes: Set<String> = []
        
        init(detector: SpatialProductDetector) {
            self.detector = detector
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let now = CACurrentMediaTime()
            
            // Project all existing products to screen coordinates every frame
            // This makes cards "track" their world position as the camera moves
            projectWorldPositionsToScreen(frame: frame)
            
            // Barcode detection at 2fps
            guard now - lastAnalysisTime >= analysisInterval else { return }
            lastAnalysisTime = now
            
            let pixelBuffer = frame.capturedImage
            let cameraTransform = frame.camera.transform
            let intrinsics = frame.camera.intrinsics
            let imageResolution = frame.camera.imageResolution
            
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
                            
                            print("🛒 SpatialDetector (AR): Barcode detected: \(payload)")
                            
                            // Estimate world position from barcode screen location
                            let bbox = observation.boundingBox
                            let worldTransform = self.estimateWorldPosition(
                                normalizedCenter: CGPoint(x: bbox.midX, y: bbox.midY),
                                cameraTransform: cameraTransform,
                                intrinsics: intrinsics,
                                imageResolution: imageResolution
                            )
                            
                            await MainActor.run {
                                let product = SpatialDetectedProduct(
                                    anchorID: UUID(),
                                    position: SIMD3<Float>(
                                        worldTransform.columns.3.x,
                                        worldTransform.columns.3.y,
                                        worldTransform.columns.3.z
                                    ),
                                    classification: "barcode",
                                    productName: payload,
                                    barcode: payload,
                                    worldAnchor: worldTransform
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
        
        // MARK: - World Position Estimation
        
        /// Estimates world position from a normalized Vision bounding box center.
        /// Uses camera intrinsics to create a ray from the camera through the
        /// barcode's screen position, placed at an estimated depth of ~0.5m.
        private func estimateWorldPosition(
            normalizedCenter: CGPoint,
            cameraTransform: simd_float4x4,
            intrinsics: simd_float3x3,
            imageResolution: CGSize
        ) -> simd_float4x4 {
            // Vision coordinates are (0,0) bottom-left, (1,1) top-right
            // Camera image coordinates: pixel space
            let pixelX = Float(normalizedCenter.x * imageResolution.width)
            let pixelY = Float((1.0 - normalizedCenter.y) * imageResolution.height) // Flip Y
            
            // Unproject pixel to camera-space ray using intrinsics
            let fx = intrinsics[0][0]
            let fy = intrinsics[1][1]
            let cx = intrinsics[2][0]
            let cy = intrinsics[2][1]
            
            // Ray direction in camera space (pointing forward along -Z)
            let dirX = (pixelX - cx) / fx
            let dirY = (pixelY - cy) / fy
            let rayDir = simd_normalize(SIMD3<Float>(dirX, -dirY, -1.0))
            
            // Place the anchor at estimated depth (~0.5m for handheld scanning)
            let estimatedDepth: Float = 0.5
            let pointInCamera = rayDir * estimatedDepth
            
            // Transform to world space
            let worldPoint = cameraTransform * SIMD4<Float>(pointInCamera.x, pointInCamera.y, pointInCamera.z, 1.0)
            
            var transform = matrix_identity_float4x4
            transform.columns.3 = worldPoint
            return transform
        }
        
        // MARK: - Screen Projection
        
        /// Projects all products' world anchors to screen coordinates.
        /// Called every AR frame to keep cards tracking their real-world positions.
        private func projectWorldPositionsToScreen(frame: ARFrame) {
            guard let arView else { return }
            let viewSize = arView.bounds.size
            guard viewSize.width > 0, viewSize.height > 0 else { return }
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                for i in 0..<self.detector.detectedProducts.count {
                    let product = self.detector.detectedProducts[i]
                    let worldPos = SIMD3<Float>(
                        product.worldAnchor.columns.3.x,
                        product.worldAnchor.columns.3.y,
                        product.worldAnchor.columns.3.z
                    )
                    
                    // Project world position to screen via ARView
                    let screenPoint = arView.project(worldPos)
                    
                    if let projected = screenPoint {
                        // Offset card slightly above the barcode position
                        let cardY = max(60, projected.y - 80)
                        self.detector.detectedProducts[i].screenPosition = SIMD3<Float>(
                            Float(projected.x),
                            Float(cardY),
                            1.0 // visible
                        )
                    } else {
                        // Behind camera or out of frustum
                        self.detector.detectedProducts[i].screenPosition.z = -1.0
                    }
                }
            }
        }
    }
}
#endif
