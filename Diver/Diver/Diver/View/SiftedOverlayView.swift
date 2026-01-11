import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Agent [DESIGN] - Renders the sifted subject mask with a Liquid Glass edge
public struct SiftedSubjectView: View {
    let siftedImage: UIImage
    let boundingBox: CGRect?
    @Binding var peelAmount: CGFloat
    
    @State private var pulse: CGFloat = 0.6
    
    public var body: some View {
        GeometryReader { geometry in
            if let box = boundingBox {
                let w = geometry.size.width
                let h = geometry.size.height
                
                // Calculate frame in SwiftUI coordinates
                // Vision: Origin Bottom-Left, Normalized
                // SwiftUI: Origin Top-Left
                let rectWidth = box.width * w
                let rectHeight = box.height * h
                let rectX = box.minX * w
                let rectY = (1 - box.maxY) * h
                
                let centerX = rectX + (rectWidth / 2)
                let centerY = rectY + (rectHeight / 2)
                
                ZStack {
                    // 1. The Pulse Glow (Bottom layer)
                    Image(uiImage: siftedImage)
                        .resizable()
                        .renderingMode(.template) // Keep template mode for coloring if needed, but usually we want original
                        // Actually, previous code used .template for the glow? 
                        // "Image(uiImage: siftedImage).renderingMode(.template)...foregroundStyle(.white)" -> White glow
                        // Yes, we want a white silhouette for the glow.
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .blur(radius: 12)
                        .opacity(pulse * (1.0 - (peelAmount * 0.5)))
                        .scaleEffect(1.0 + (peelAmount * 0.12)) // Default anchor is center
                    
                    // 2. The Sharp Outline
                    Image(uiImage: siftedImage)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white.opacity(0.8))
                        .blur(radius: 1)
                        .scaleEffect(1.0 + (peelAmount * 0.11))
                    
                    // 3. The Main Subject
                    Image(uiImage: siftedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(1.0 + (peelAmount * 0.1))
                        .offset(y: -peelAmount * 30) // Subtle lift
                        .shadow(color: .black.opacity(0.4 * peelAmount), radius: 15, y: 15)
                }
                .frame(width: rectWidth, height: rectHeight)
                .position(x: centerX, y: centerY)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = 1.0
            }
        }
    }
}
