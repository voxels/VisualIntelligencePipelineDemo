import SwiftUI
import SwiftData
import DiverShared
import DiverKit
import CoreImage.CIFilterBuiltins

/// Specialized profile view for displaying QR Code captures, rendering the barcode payload,
/// generating a scannable crisp barcode image, and providing inline web viewing for URLs.
struct QRCodeProfileView: View {
    let item: ProcessedItem
    
    var body: some View {
        if let context = item.qrContext {
            VStack {
                QRCodeGeneratorView(context: context)
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
    }
}

// MARK: - QR Code View
struct QRCodeGeneratorView: View {
    let context: QRCodeContext
    
    // CoreImage properties for barcode generation
    private let contextGen = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. Visually Re-generated QR Code
            if let image = generateQRCode(from: context.payload) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                Image(systemName: "qrcode.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            
            // 2. Payload Text
            VStack(spacing: 4) {
                Text("Scanned Content")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Text(context.payload)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            
            // 3. Inline Web View (if payload is a URL)
            if let url = URL(string: context.payload), ["http", "https"].contains(url.scheme?.lowercased()) {
                Divider()
                RichWebView(url: url)
                    .frame(height: 300)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    /// Generates a crisp, scannable UIImage from a string payload using CoreImage
    private func generateQRCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            // Scale up by 10x to retain sharpness when displayed
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = contextGen.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}
