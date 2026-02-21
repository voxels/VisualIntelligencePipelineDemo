import Foundation
import CoreML
import Vision
import CoreVideo
import CoreImage

/// Protocol defining the contract for pixel-perfect structural segmentation on the edge.
public protocol SAM2Segmenting: Sendable {
    func segment(pixelBuffer: CVPixelBuffer) async throws -> CGImage?
}

/// Errors thrown by the SAM 2 Segmentation Service
public enum SAM2Error: Error {
    case modelNotFound
    case unsupportedInput
    case generationFailed
    case missingOutput
}

/// Runs Apple's SAM 2.1 Small CoreML model natively on the iOS/macOS Neural Engine.
/// Generates pixel-perfect alpha masks for highlighted subjects in a camera feed.
public final class SAM2SegmentationService: SAM2Segmenting, Sendable {
    
    // MARK: - Properties
    
    nonisolated(unsafe) private let model: VNCoreMLModel?
    private let context = CIContext(options: nil)
    
    // MARK: - Initialization
    
    public init() {
        // Load the 150MB sam2.1-small.mlpackage provisioned natively by EdgeModelProvisioner
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelURL = appSupport.appendingPathComponent("Models/sam2.1-small.mlpackage")
            
            guard FileManager.default.fileExists(atPath: modelURL.path) else {
                print("⚠️ [SAM2Service] Could not find sam2.1-small.mlpackage in Application Support/Models. Waiting for Provisioner...")
                self.model = nil
                return
            }
            // Compile the model if necessary (usually cached by iOS)
            let compiledURL = try MLModel.compileModel(at: modelURL)
            
            // Configure the model to utilize the Neural Engine (if available) and GPU
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            let mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
            self.model = try VNCoreMLModel(for: mlModel)
            print("✅ [SAM2Service] Successfully loaded SAM 2.1 CoreML model into Neural Engine.")
            
        } catch {
            print("❌ [SAM2Service] Failed to load SAM 2.1 model: \(error)")
            self.model = nil
        }
    }
    
    // MARK: - Segmentation
    
    /// Processes a live camera frame through the Neural Engine to generate a structural mask.
    /// - Parameter pixelBuffer: The CVPixelBuffer frame from the AVCaptureVideoDataOutput.
    /// - Returns: A CGImage representing the alpha mask of the detected subject.
    public func segment(pixelBuffer: CVPixelBuffer) async throws -> CGImage? {
        guard let vnModel = model else {
            throw SAM2Error.modelNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // SAM 2.1 CoreML typically outputs a multiarray representing the mask probabilities
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let firstResult = results.first,
                      let multiArray = firstResult.featureValue.multiArrayValue else {
                    continuation.resume(throwing: SAM2Error.missingOutput)
                    return
                }
                
                // Convert the MLMultiArray mask back into a visual CGImage
                do {
                    if let cgImage = try self.convertMultiArrayToCGImage(multiArray) {
                        continuation.resume(returning: cgImage)
                    } else {
                        continuation.resume(throwing: SAM2Error.generationFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            // SAM expects the image to be cropped/scaled to a specific size (usually 1024x1024)
            request.imageCropAndScaleOption = .scaleFit
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Converts the raw float Neural Engine mask array into a renderable binary alpha mask.
    private func convertMultiArrayToCGImage(_ multiArray: MLMultiArray) throws -> CGImage? {
        // Fast path: CoreML provides an image interpretation sequence if the model exports it
        let ciImage = CIImage(cvPixelBuffer: multiArray.pixelBuffer!)
        
        // Return a renderable CGImage matching the exact pixel map
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}
