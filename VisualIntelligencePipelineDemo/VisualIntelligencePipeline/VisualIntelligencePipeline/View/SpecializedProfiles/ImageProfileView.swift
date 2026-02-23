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
            
            // 3. ML-Sharp RealityKit Splat Viewer (Stub for future PR)
            // if let splatData = item.mlSharpData {
            //     MLSharpSplatView(data: splatData)
            // }
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
