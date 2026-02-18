import Foundation
import Vision
import AVFoundation
import CoreMedia

#if canImport(UIKit)
import UIKit
#endif

/// Service for extracting aesthetically-scored frames from videos.
/// Uses Apple's Vision framework for ML-based aesthetic scoring,
/// bundled with FeaturePrint generation in a single handler.perform() per frame.
/// Safety: @unchecked Sendable is correct — only private `let` constants
/// (similarityThreshold, framesToEvaluate), no mutable state.
@available(iOS 17.0, macOS 14.0, *)
public final class AestheticsScoringService: AestheticsScoring, @unchecked Sendable {
    
    /// Similarity threshold for deduplication (lower = more similar)
    private let similarityThreshold: Float = 0.5
    
    /// Number of frames to sample from a video
    private let framesToEvaluate: Int = 100
    
    public init() {}
    
    // MARK: - Video Frame Extraction
    
    /// Extract the best N frames from a video based on aesthetic scoring.
    /// Uses FeaturePrint to avoid selecting visually similar frames.
    /// Aesthetics + FeaturePrint are bundled into a single Vision handler.perform() per frame.
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
                
                // Bundle aesthetics + feature print into a single Vision pass
                let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
                let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([aestheticsRequest, featurePrintRequest])
                
                let score = aestheticsRequest.results?.first?.overallScore ?? 0.0
                let featurePrint = featurePrintRequest.results?.first as? VNFeaturePrintObservation
                
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
    
    // MARK: - Photo Scoring
    
    /// Score and return a thumbnail from a photo using VNCalculateImageAestheticsScoresRequest.
    public func bestThumbnailFromImage(_ cgImage: CGImage) async throws -> Thumbnail {
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let score = request.results?.first?.overallScore ?? 0.0
        return Thumbnail(image: cgImage, frame: nil, score: score)
    }
}
