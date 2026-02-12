import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

/// Specialized service for handling document-specific image processing operations
/// such as perspective correction (rectification), cropping, and enhancement.
public struct DocumentManager: Sendable {
    public init() {}
    
    /// Rectifies an image based on a detected rectangle observation.
    /// - Parameters:
    ///   - image: The source CGImage.
    ///   - observation: The VNRectangleObservation containing the document bounds.
    /// - Returns: The rectified image data as JPEG, or nil if processing fails.
    public func rectifyImage(_ image: CGImage, using observation: VNRectangleObservation) -> Data? {
        let ciImage = CIImage(cgImage: image)
        
        // Convert Vision normalized coordinates to CoreImage coordinates
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        let topLeft = CGPoint(x: observation.topLeft.x * width, y: observation.topLeft.y * height)
        let topRight = CGPoint(x: observation.topRight.x * width, y: observation.topRight.y * height)
        let bottomLeft = CGPoint(x: observation.bottomLeft.x * width, y: observation.bottomLeft.y * height)
        let bottomRight = CGPoint(x: observation.bottomRight.x * width, y: observation.bottomRight.y * height)
        
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = topLeft
        filter.topRight = topRight
        filter.bottomLeft = bottomLeft
        filter.bottomRight = bottomRight
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let context = CIContext()
        // Convert back to CGImage and then Data
        if let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) {
             #if canImport(UIKit)
             let uiImage = UIImage(cgImage: cgOutput)
             return uiImage.jpegData(compressionQuality: 0.8)
             #elseif canImport(AppKit)
             let bitmapRep = NSBitmapImageRep(cgImage: cgOutput)
             return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
             #else
             return nil
             #endif
        }
        return nil
    }
}
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
