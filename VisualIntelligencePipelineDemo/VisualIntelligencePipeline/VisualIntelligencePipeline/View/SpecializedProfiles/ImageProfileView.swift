import SwiftUI
import SwiftData
import DiverShared
import DiverKit

/// Specialized profile view for fallback visual captures that lack strong domain contexts
/// (like products, documents, or places) but still contain rich visual metadata.
/// 
/// Handles rendering:
/// 1. Vision Framework Aesthetics / Saliency Scores
/// 2. Raw EXIF Camera/Lens Metadata
/// 3. RealityKit ML-Sharp 3D Gaussian Splat Data
struct ImageProfileView: View {
    let item: ProcessedItem
    @State private var isGeneratingSplat: Bool = false
    @State private var edgeError: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            
            // 1. Aesthetics / Quality Section
            if let aesthetics = item.aestheticsScore {
                AestheticsCardView(score: aesthetics)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            
            // 2. EXIF Metadata Section
            EXIFMetadataSection(item: item)
                .padding(.horizontal)
            
            // 3. ML-Sharp RealityKit USDZ Viewer
            if let usdzData = item.mlSharpData {
                 MLSharpSplatView(splatData: usdzData)
            } else {
                 Button(action: {
                     generateSplat()
                 }) {
                     if isGeneratingSplat {
                         ProgressView()
                             .progressViewStyle(CircularProgressViewStyle())
                     } else {
                         Label("Generate 3D Splat (ML-Sharp)", systemImage: "cube.transparent")
                             .font(.headline)
                             .foregroundStyle(.white)
                             .padding(.vertical, 12)
                             .frame(maxWidth: .infinity)
                             .background(Color.blue.gradient)
                             .clipShape(RoundedRectangle(cornerRadius: 12))
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal)
                 
                 if let err = edgeError {
                     Text(err)
                         .font(.caption)
                         .foregroundStyle(.red)
                         .padding(.horizontal)
                 }
            }
        }
    }
    
    private func generateSplat() {
        guard let imageData = item.rawPayload else {
            edgeError = "Missing raw image payload"
            return
        }
        isGeneratingSplat = true
        edgeError = nil
        
        Task {
            do {
                let router = await MainActor.run { return Services.shared.edgeRouter }
                let system = await MainActor.run { return Services.shared.actorSystem }
                
                if let router = router, let system = system {
                    
                    let decision = await router.shouldOffload(task: .visionAnalysis)
                    if case .edge(let node, _) = decision, node.availableModels.contains("ml-sharp") {
                        let identity = EdgeActorID(id: "EdgeInference", nodeName: node.deviceName)
                        let edgeActor = try EdgeInferenceActor.resolve(id: identity, using: system)
                        
                        let usdzData = try await edgeActor.runMLSharp(imageData: imageData)
                        await MainActor.run {
                            withAnimation {
                                self.item.mlSharpData = usdzData
                                try? self.item.modelContext?.save()
                                self.isGeneratingSplat = false
                            }
                        }
                    } else {
                       throw NSError(domain: "ImageProfileView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No edge node connected with ml-sharp capability."])
                    }
                }
            } catch {
                await MainActor.run {
                    self.edgeError = error.localizedDescription
                    self.isGeneratingSplat = false
                }
            }
        }
    }
}

// MARK: - Aesthetics Component
struct AestheticsCardView: View {
    let score: Double
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(score, 0.0), 1.0)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.red, .orange, .green, .blue]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                
                Text(String(format: "%.1f", score * 10))
                    .font(.caption2.bold())
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Aesthetics Score")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(qualityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var qualityText: String {
        if score > 0.8 { return "Professional Quality" }
        if score > 0.6 { return "High Quality" }
        if score > 0.4 { return "Average Quality" }
        return "Low Quality"
    }
}

// MARK: - EXIF Metadata Component
struct EXIFMetadataSection: View {
    let item: ProcessedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Information")
                .font(.headline)
            
            VStack(spacing: 8) {
                if let date = item.originalDate {
                    InfoRow(icon: "calendar", title: "Date Captured", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                
                if let location = item.location {
                    InfoRow(icon: "mappin.and.ellipse", title: "Location", value: location)
                }
                
                if let filename = item.filename {
                    InfoRow(icon: "doc", title: "Filename", value: filename)
                }
                
                if let size = item.fileSize {
                    InfoRow(icon: "externaldrive", title: "File Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
            }
            .padding()
            .glassEffect()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#if os(iOS) || os(visionOS)
import RealityKit

/// A RealityKit view that renders a 3D semantic representation (Gaussian Splat / Point Cloud)
/// returned by the Apple ml-sharp edge service.
public struct MLSharpSplatView: View {
    let splatData: Data
    
    // Gestures state for 3D manipulation
    @State private var rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var scale: Float = 1.0
    
    // The main container entity
    @State private var rootEntity = Entity()
    
    public init(splatData: Data) {
        self.splatData = splatData
    }
    
    public var body: some View {
        RealityView { content in
            // Add the root entity to the scene
            content.add(rootEntity)
            
            // Write the USDZ data to a temporary file because RealityKit requires a URL to load models
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
            do {
                try splatData.write(to: tempURL)
                
                // Load the USDZ mesh asynchronously
                Task {
                    do {
                        let loadRequest = try await Entity.load(contentsOf: tempURL)
                        
                        await MainActor.run {
                            // Center the loaded entity
                            loadRequest.position = [0, 0, 0]
                            rootEntity.addChild(loadRequest)
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                        }
                    } catch {
                        print("Failed to load USDZ: \(error)")
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }
            } catch {
                print("Failed to write temp USDZ file: \(error)")
            }
            
        } update: { content in
            // Apply gesture transforms
            rootEntity.transform.rotation = rotation
            rootEntity.transform.scale = [scale, scale, scale]
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Orbit rotation around Y and X axis based on drag
                    let deltaX = Float(value.translation.width) * 0.01
                    let deltaY = Float(value.translation.height) * 0.01
                    
                    let rotY = simd_quatf(angle: deltaX, axis: [0, 1, 0])
                    let rotX = simd_quatf(angle: deltaY, axis: [1, 0, 0])
                    
                    rotation = rotation * rotY * rotX
                }
        )
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    // Scale between 0.5x and 3.0x
                    let newScale = Float(value.magnification)
                    scale = min(max(newScale, 0.5), 3.0)
                }
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arkit")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7))
                .padding(12)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
                .padding(8)
        }
    }
}
#endif
