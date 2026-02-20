#if canImport(UIKit)
import UIKit
import ImageIO

public extension UIImage {
    /// Returns a new UIImage with the orientation "baked in" (normalized to .up).
    /// This is useful when displaying images in views that ignore the imageOrientation property,
    /// or when preparing images for processing that expects upright orientation.
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
    
    /// Initialize with data and attempt to explicitly read orientation from EXIF
    /// if the standard init(data:) fails to handle it correctly.
    static func fromDataWithOrientation(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        
        let validOrientation: UIImage.Orientation
        
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let rawOrientation = properties[kCGImagePropertyOrientation as String] as? UInt32,
           let cgOrientation = CGImagePropertyOrientation(rawValue: rawOrientation) {
            
            // Map CGImagePropertyOrientation to UIImage.Orientation
            switch cgOrientation {
            case .up: validOrientation = .up
            case .upMirrored: validOrientation = .upMirrored
            case .down: validOrientation = .down
            case .downMirrored: validOrientation = .downMirrored
            case .left: validOrientation = .left
            case .leftMirrored: validOrientation = .leftMirrored
            case .right: validOrientation = .right
            case .rightMirrored: validOrientation = .rightMirrored
            }
        } else {
            validOrientation = .up
        }
        
        // Re-create the image with the explicit orientation
        if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: cgImage, scale: 1.0, orientation: validOrientation)
        }
        
        return UIImage(data: data)
    }
}
#endif
