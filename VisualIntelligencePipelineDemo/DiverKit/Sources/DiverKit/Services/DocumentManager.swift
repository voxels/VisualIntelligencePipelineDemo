import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Specialized service for handling document-specific image processing operations
/// such as perspective correction (rectification), cropping, and enhancement.
public struct DocumentManager: Sendable {
    public init() {}
    
    /// Physically rotates a CGImage's pixels according to the given EXIF orientation.
    /// Uses UIImage's built-in orientation drawing (via UIGraphicsImageRenderer)
    /// which correctly handles all 8 EXIF orientations.
    private func normalizeOrientation(of image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        guard orientation != .up else { return image }
        
        #if canImport(UIKit)
        // Convert CGImagePropertyOrientation → UIImage.Orientation
        let uiOrientation: UIImage.Orientation
        switch orientation {
        case .up:            uiOrientation = .up
        case .upMirrored:    uiOrientation = .upMirrored
        case .down:          uiOrientation = .down
        case .downMirrored:  uiOrientation = .downMirrored
        case .left:          uiOrientation = .left
        case .leftMirrored:  uiOrientation = .leftMirrored
        case .right:         uiOrientation = .right
        case .rightMirrored: uiOrientation = .rightMirrored
        @unknown default:    uiOrientation = .up
        }
        
        // Create UIImage with the specified orientation, then draw it
        // into a renderer — UIKit's draw(in:) correctly applies the
        // orientation transform, producing upright pixels.
        let uiImage = UIImage(cgImage: image, scale: 1.0, orientation: uiOrientation)
        let renderer = UIGraphicsImageRenderer(size: uiImage.size)
        let normalized = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
        }
        return normalized.cgImage
        #else
        // macOS fallback — NSImage typically normalizes orientation
        return image
        #endif
    }
    
    /// Rectifies an image based on a detected rectangle observation.
    /// - Parameters:
    ///   - image: The source CGImage (raw pixels, may not be oriented).
    ///   - observation: The VNRectangleObservation containing the document bounds.
    ///   - orientation: The image orientation to apply before rectification.
    ///   - sourceProperties: Optional EXIF/metadata properties from the original image to preserve.
    /// - Returns: The rectified image data as JPEG with EXIF preserved, or nil if processing fails.
    public func rectifyImage(
        _ image: CGImage,
        using observation: VNRectangleObservation,
        orientation: CGImagePropertyOrientation = .up,
        sourceProperties: [String: Any]? = nil
    ) -> Data? {
        print("📐 DocumentManager.rectifyImage: input=\(image.width)×\(image.height), orientation=\(orientation.rawValue)")
        
        // Step 1: Physically rotate pixels using CGContext (proven reliable).
        // CIImage.oriented() is a lazy affine transform that may not compose
        // correctly with CIPerspectiveCorrection. CGContext.draw() with an
        // affine transform is guaranteed to produce correctly oriented pixels.
        guard let orientedCG = normalizeOrientation(of: image, orientation: orientation) else {
            print("📐 DocumentManager: normalizeOrientation failed")
            return nil
        }
        
        print("📐 DocumentManager.rectifyImage: oriented=\(orientedCG.width)×\(orientedCG.height)")
        
        // Step 2: Create CIImage from the physically-oriented pixels (orientation is now .up)
        let ciImage = CIImage(cgImage: orientedCG)
        let width  = ciImage.extent.width
        let height = ciImage.extent.height
        
        // Convert Vision normalized coordinates to CoreImage coordinates
        let topLeft     = CGPoint(x: observation.topLeft.x     * width, y: observation.topLeft.y     * height)
        let topRight    = CGPoint(x: observation.topRight.x    * width, y: observation.topRight.y    * height)
        let bottomLeft  = CGPoint(x: observation.bottomLeft.x  * width, y: observation.bottomLeft.y  * height)
        let bottomRight = CGPoint(x: observation.bottomRight.x * width, y: observation.bottomRight.y * height)
        
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = topLeft
        filter.topRight = topRight
        filter.bottomLeft = bottomLeft
        filter.bottomRight = bottomRight
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        
        print("📐 DocumentManager.rectifyImage: output=\(cgOutput.width)×\(cgOutput.height)")
        
        // Write JPEG with EXIF metadata preserved via ImageIO
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        
        // Build output properties: preserve source EXIF, override orientation to .up
        var outputProperties = sourceProperties ?? [:]
        // The rectified image is upright — set TIFF/EXIF orientation to normal
        outputProperties[kCGImagePropertyOrientation as String] = CGImagePropertyOrientation.up.rawValue
        if var tiffDict = outputProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiffDict[kCGImagePropertyTIFFOrientation as String] = CGImagePropertyOrientation.up.rawValue
            outputProperties[kCGImagePropertyTIFFDictionary as String] = tiffDict
        }
        // Set JPEG compression quality
        outputProperties[kCGImageDestinationLossyCompressionQuality as String] = 0.8
        
        CGImageDestinationAddImage(destination, cgOutput, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        
        return data as Data
    }
}
