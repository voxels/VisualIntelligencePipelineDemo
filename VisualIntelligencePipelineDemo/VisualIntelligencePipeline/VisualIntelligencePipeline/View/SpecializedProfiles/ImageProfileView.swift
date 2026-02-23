import SwiftUI
import SwiftData
import DiverShared

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
                if let router = await MainActor.run({ Services.shared.edgeRouter }),
                   let system = await MainActor.run({ Services.shared.actorSystem }) {
                    
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
