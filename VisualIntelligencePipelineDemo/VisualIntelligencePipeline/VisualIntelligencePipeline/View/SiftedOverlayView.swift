import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Agent [DESIGN] - Renders the sifted subject mask with a Liquid Glass edge
public struct SiftedSubjectView: View {
    let siftedImage: UIImage
    let boundingBox: CGRect?
    /// The size of the backing image so we can compute the aspect-fit inset.
    var backingImageSize: CGSize = .zero
    @Binding var peelAmount: CGFloat
    
    @State private var pulse: CGFloat = 0.6
    @State private var showingShareSheet = false
    
    public var body: some View {
        GeometryReader { geometry in
            if let box = boundingBox {
                // Compute the rect of the image within the view after aspect-fit
                let imageRect = aspectFitRect(
                    imageSize: backingImageSize,
                    in: geometry.size
                )
                
                let w = imageRect.width
                let h = imageRect.height
                
                // Calculate frame in SwiftUI coordinates
                // Vision: Origin Bottom-Left, Normalized
                // SwiftUI: Origin Top-Left
                let rectWidth = box.width * w
                let rectHeight = box.height * h
                let rectX = imageRect.minX + box.minX * w
                let rectY = imageRect.minY + (1 - box.maxY) * h
                
                let centerX = rectX + (rectWidth / 2)
                let centerY = rectY + (rectHeight / 2)
                
                ZStack {
                    // 0. Localized material blur behind the subject
                    Image(uiImage: siftedImage)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .blur(radius: 20)
                        .opacity(0.3)
                        .glass(cornerRadius: 16)
                    
                    // 1. The Pulse Glow (Bottom layer)
                    Image(uiImage: siftedImage)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .blur(radius: 12)
                        .opacity(pulse * (1.0 - (peelAmount * 0.5)))
                        .scaleEffect(1.0 + (peelAmount * 0.12))
                    
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
                        .offset(y: -peelAmount * 30)
                        .shadow(color: .black.opacity(0.4 * peelAmount), radius: 15, y: 15)
                }
                .frame(width: rectWidth, height: rectHeight)
                .position(x: centerX, y: centerY)
                .contextMenu {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(siftedImage, nil, nil, nil)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = 1.0
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let pngData = siftedImage.pngData() {
                ShareSheet(activityItems: [pngData])
            }
        }
    }
    
    /// Computes the rect of an image displayed with `.aspectRatio(contentMode: .fit)`
    /// within a container of the given size.
    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        let fitWidth: CGFloat
        let fitHeight: CGFloat
        
        if imageAspect > containerAspect {
            fitWidth = containerSize.width
            fitHeight = containerSize.width / imageAspect
        } else {
            fitHeight = containerSize.height
            fitWidth = containerSize.height * imageAspect
        }
        
        let x = (containerSize.width - fitWidth) / 2
        let y = (containerSize.height - fitHeight) / 2
        
        return CGRect(x: x, y: y, width: fitWidth, height: fitHeight)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
