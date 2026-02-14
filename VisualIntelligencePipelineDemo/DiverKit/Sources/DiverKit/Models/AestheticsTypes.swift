import Foundation
import CoreMedia
import Vision
import SwiftUI
import CoreLocation

/// Represents a video frame with its aesthetic score and feature print for similarity comparison.
public struct Frame {
    /// The timestamp of the frame in the video
    public let time: CMTime
    /// The aesthetic score (0.0-1.0)
    public let score: Float
    /// The feature print observation for similarity comparison
    public let observation: VNFeaturePrintObservation
    
    public init(time: CMTime, score: Float, observation: VNFeaturePrintObservation) {
        self.time = time
        self.score = score
        self.observation = observation
    }
}

/// A thumbnail extracted from a video or image, with associated aesthetic scoring data.
public final class Thumbnail: Identifiable, @unchecked Sendable {
    public let id = UUID()
    /// The image extracted from the video frame or photo
    public let image: CGImage
    /// The frame data (for videos)
    public let frame: Frame?
    /// The persisted file path (after saving to disk)
    public var path: String?
    /// The aesthetic score (for photos without Frame data)
    public let score: Float
    
    public init(image: CGImage, frame: Frame? = nil, path: String? = nil, score: Float = 0.0) {
        self.image = image
        self.frame = frame
        self.path = path
        self.score = frame?.score ?? score
    }
}

/// Asset metadata extracted during import
public struct ImportedAsset: Identifiable, Sendable {
    public let id: String
    public let data: Data
    public let isVideo: Bool
    public let isScreenshot: Bool
    public let isScreenRecording: Bool
    public let creationDate: Date?
    public let location: CLLocationCoordinate2D?
    public let originalFilename: String?
    /// Photos library item identifier for fetching original asset on-demand
    public let photosItemIdentifier: String?
    
    public init(
        id: String = UUID().uuidString,
        data: Data,
        isVideo: Bool = false,
        isScreenshot: Bool = false,
        isScreenRecording: Bool = false,
        creationDate: Date? = nil,
        location: CLLocationCoordinate2D? = nil,
        originalFilename: String? = nil,
        photosItemIdentifier: String? = nil
    ) {
        self.id = id
        self.data = data
        self.isVideo = isVideo
        self.isScreenshot = isScreenshot
        self.isScreenRecording = isScreenRecording
        self.creationDate = creationDate
        self.location = location
        self.originalFilename = originalFilename
        self.photosItemIdentifier = photosItemIdentifier
    }
}

