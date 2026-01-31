import Foundation
import Vision
import AVFoundation
import CoreMedia

#if canImport(UIKit)
import UIKit
#endif

/// Service for extracting aesthetically-scored frames from videos and scoring images.
/// Uses Apple's Vision framework for image analysis.
@available(iOS 17.0, macOS 14.0, *)
public final class AestheticsScoringService: @unchecked Sendable {
    
    /// Similarity threshold for deduplication (lower = more similar)
    private let similarityThreshold: Float = 0.5
    
    /// Number of frames to sample from a video
    private let framesToEvaluate: Int = 100
    
    public init() {}
    
    // MARK: - Image Scoring
    
    /// Calculate the aesthetic score for a single image using heuristics.
    /// Based on brightness, contrast, and edge detection for sharpness.
    /// - Returns: Score between 0.0 and 1.0
    public func scoreImage(_ cgImage: CGImage) async throws -> Float {
        // Use simple heuristics for aesthetic scoring
        let brightness = calculateBrightness(cgImage)
        let contrast = calculateContrast(cgImage)
        let sharpness = await calculateSharpness(cgImage)
        
        // Combine metrics (weights can be tuned)
        let score = (brightness * 0.3) + (contrast * 0.3) + (sharpness * 0.4)
        return score
    }
    
    // MARK: - Video Frame Extraction
    
    /// Extract the best N frames from a video based on aesthetic scoring.
    /// Uses FeaturePrint to avoid selecting visually similar frames.
    /// - Parameters:
    ///   - videoURL: URL to the video file
    ///   - count: Number of frames to extract (default 5)
    /// - Returns: Array of Thumbnails with the highest aesthetic scores
    public func extractBestFrames(from videoURL: URL, count: Int = 5) async throws -> [Thumbnail] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)
        
        guard totalDuration > 0 else { return [] }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        // Sample frames at regular intervals
        let interval = totalDuration / Double(framesToEvaluate)
        var candidates: [(time: CMTime, image: CGImage, score: Float, featurePrint: VNFeaturePrintObservation?)] = []
        
        for i in 0..<framesToEvaluate {
            let timeSeconds = Double(i) * interval
            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
            
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let score = try await scoreImage(cgImage)
                let featurePrint = generateFeaturePrint(for: cgImage)
                
                candidates.append((time: time, image: cgImage, score: score, featurePrint: featurePrint))
            } catch {
                continue // Skip frames that fail to extract
            }
        }
        
        // Sort by score descending
        candidates.sort { $0.score > $1.score }
        
        // Select top frames ensuring diversity using feature prints
        var selectedFrames: [(time: CMTime, image: CGImage, score: Float)] = []
        
        for candidate in candidates {
            guard selectedFrames.count < count else { break }
            
            var isSimilar = false
            
            // Check similarity against already selected frames
            if let candidatePrint = candidate.featurePrint {
                for selected in selectedFrames {
                    if let selectedPrint = candidates.first(where: { CMTimeCompare($0.time, selected.time) == 0 })?.featurePrint {
                        var distance: Float = 0
                        do {
                            try candidatePrint.computeDistance(&distance, to: selectedPrint)
                            if distance < similarityThreshold {
                                isSimilar = true
                                break
                            }
                        } catch {
                            continue
                        }
                    }
                }
            }
            
            if !isSimilar {
                selectedFrames.append((time: candidate.time, image: candidate.image, score: candidate.score))
            }
        }
        
        // Convert to Thumbnails
        return selectedFrames.map { frame in
            Thumbnail(image: frame.image, frame: nil, path: nil, score: frame.score)
        }
    }
    
    // MARK: - Feature Print Generation
    
    /// Generate feature print synchronously to avoid Sendable issues
    private nonisolated func generateFeaturePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }
    
    // MARK: - Image Quality Metrics
    
    private func calculateBrightness(_ image: CGImage) -> Float {
        // Simple brightness estimation based on average pixel luminance
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }
        
        let bytesPerPixel = image.bitsPerPixel / 8
        let totalPixels = image.width * image.height
        var totalBrightness: Double = 0
        
        // Sample every 100th pixel for performance
        let step = max(1, totalPixels / 1000)
        var sampledCount = 0
        
        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: step * bytesPerPixel) {
            let r = Double(bytes[i])
            let g = Double(bytes[i + 1])
            let b = Double(bytes[i + 2])
            
            // Luminance formula
            let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            totalBrightness += luminance
            sampledCount += 1
        }
        
        let avgBrightness = totalBrightness / Double(max(1, sampledCount))
        
        // Ideal brightness around 0.5, penalize too dark or too bright
        let score = 1.0 - abs(avgBrightness - 0.5) * 2
        return Float(max(0, min(1, score)))
    }
    
    private func calculateContrast(_ image: CGImage) -> Float {
        // Estimate contrast based on standard deviation of luminance
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }
        
        let bytesPerPixel = image.bitsPerPixel / 8
        let totalPixels = image.width * image.height
        var luminances: [Double] = []
        
        // Sample every 100th pixel
        let step = max(1, totalPixels / 1000)
        
        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: step * bytesPerPixel) {
            let r = Double(bytes[i])
            let g = Double(bytes[i + 1])
            let b = Double(bytes[i + 2])
            let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            luminances.append(luminance)
        }
        
        guard !luminances.isEmpty else { return 0.5 }
        
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        let variance = luminances.map { pow($0 - mean, 2) }.reduce(0, +) / Double(luminances.count)
        let stdDev = sqrt(variance)
        
        // Higher std dev = more contrast (normalize to 0-1)
        return Float(min(1, stdDev * 4))
    }
    
    private func calculateSharpness(_ image: CGImage) async -> Float {
        // Use Vision to detect edges as a proxy for sharpness
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                // More detected rectangles = sharper image (rough heuristic)
                let count = request.results?.count ?? 0
                let score = min(1.0, Float(count) / 10.0)
                continuation.resume(returning: score)
            }
            request.minimumConfidence = 0.3
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: 0.5)
            }
        }
    }
    
    // MARK: - Photo Scoring
    
    /// Score and return a thumbnail from a photo
    public func bestThumbnailFromImage(_ cgImage: CGImage) async throws -> Thumbnail {
        let score = try await scoreImage(cgImage)
        return Thumbnail(image: cgImage, frame: nil, score: score)
    }
}
