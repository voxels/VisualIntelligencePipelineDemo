import Foundation
import Photos
import AVFoundation
import Vision

#if canImport(UIKit)
import UIKit
#endif

/// Service for loading image/video data from the Photos library on-demand
/// using a stored asset identifier (localIdentifier from PHAsset)
@MainActor
public final class PhotosAssetLoader {
    
    public static let shared = PhotosAssetLoader()
    
    private init() {}
    
    /// Load image data from Photos library using a local identifier
    /// - Parameter identifier: The PHAsset localIdentifier stored in ProcessedItem
    /// - Returns: Image data if found and accessible, nil otherwise
    public func loadImageData(identifier: String) async -> Data? {
        // Request authorization if needed
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            print("⚠️ PhotosAssetLoader: Not authorized to access Photos library")
            return nil
        }
        
        // Fetch the asset
        var asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        
        // Fallback: Try appending standard suffix if missing (heuristics for raw pickle IDs)
        if asset == nil && !identifier.contains("/") {
            let standardID = identifier + "/L0/001"
            asset = PHAsset.fetchAssets(withLocalIdentifiers: [standardID], options: nil).firstObject
            if asset != nil {
                print("🔄 PhotosAssetLoader: Resolved asset using suffix heuristic: \(standardID)")
            }
        }
        
        guard let asset = asset else {
            print("⚠️ PhotosAssetLoader: Asset not found for identifier: \(identifier)")
            return nil
        }
        
        // Load the image data
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            if asset.mediaType == .video {
                // For videos, get the video data
                loadVideoData(asset: asset) { data in
                    continuation.resume(returning: data)
                }
            } else {
                // For images
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }
        }
    }
    
    /// Load video data from a PHAsset
    private func loadVideoData(asset: PHAsset, completion: @escaping (Data?) -> Void) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let urlAsset = avAsset as? AVURLAsset else {
                completion(nil)
                return
            }
            
            // Read the video file data
            do {
                let data = try Data(contentsOf: urlAsset.url)
                completion(data)
            } catch {
                print("⚠️ PhotosAssetLoader: Failed to read video data: \(error)")
                completion(nil)
            }
        }
    }
    
    /// Load a thumbnail image (more memory efficient than full data)
    /// - Parameters:
    ///   - identifier: The PHAsset localIdentifier
    ///   - size: Target size for the thumbnail
    /// - Returns: Thumbnail image data as JPEG
    public func loadThumbnail(identifier: String, size: CGSize = CGSize(width: 300, height: 300)) async -> Data? {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            return nil
        }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            
            #if canImport(UIKit)
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !resumed else { return }
                
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                
                if let image = image, !isDegraded {
                    let data = image.jpegData(compressionQuality: 0.8)
                    resumed = true
                    continuation.resume(returning: data)
                } else if error != nil || isCancelled {
                    resumed = true
                    continuation.resume(returning: nil)
                } else {
                    // Fallback for degraded or nil image without error
                    // If it is NOT degraded but image is nil, it's a failure.
                    // If it IS degraded, we wait for the next callback... UNLESS this is the last one?
                    // PHImageManager guarantees a final callback.
                    // But if we get (nil, nil) and !isDegraded... fail safe:
                    if !isDegraded && image == nil {
                         print("⚠️ PhotosAssetLoader: Thumbnail load failed (nil image, no error)")
                         resumed = true
                         continuation.resume(returning: nil)
                    }
                }
            }
            #else
            continuation.resume(returning: nil)
            #endif
        }
    }
    
    /// Check if an asset exists and is accessible
    public func assetExists(identifier: String) async -> Bool {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            return false
        }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return fetchResult.count > 0
    }
    
    public func requestAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
        }
        
        return status
    }
    
    // MARK: - Smart Frame Extraction
    
    /// Load the best representative frame for an asset (Video or Image)
    /// For videos: Extracts the most aesthetically pleasing frame using `AestheticsScoringService`
    /// For images: Returns the high-quality image data
    /// - Parameter identifier: The PHAsset localIdentifier
    /// - Returns: Data object representing the best image/frame
    public func loadBestFrame(identifier: String) async -> Data? {
        // Request authorization if needed
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            print("⚠️ PhotosAssetLoader: Not authorized to access Photos library")
            return nil
        }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            print("⚠️ PhotosAssetLoader: Asset not found for identifier: \(identifier)")
            return nil
        }
        
        if asset.mediaType == .video {
            return await loadBestVideoFrame(asset: asset)
        } else {
            return await loadImageData(identifier: identifier)
        }
    }
    
    private func loadBestVideoFrame(asset: PHAsset) async -> Data? {
        // 1. Get AVAsset URL
        let videoOptions = PHVideoRequestOptions()
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.deliveryMode = .highQualityFormat
        
        // Use URL (Sendable) instead of AVAsset to avoid data race warning
        let videoURL: URL? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        
        guard let url = videoURL else {
            print("⚠️ PhotosAssetLoader: Could not get AVURLAsset URL for video, falling back to poster frame")
            return await loadImageData(identifier: asset.localIdentifier)
        }
        
        // 2. Extract best frame
        if #available(iOS 17.0, macOS 14.0, *) {
            do {
                let aestheticsService = AestheticsScoringService()
                let bestFrames = try await aestheticsService.extractBestFrames(from: url, count: 1)
                
                if let bestFrame = bestFrames.first?.image {
                    #if canImport(UIKit)
                    let uiImage = UIImage(cgImage: bestFrame)
                    return uiImage.jpegData(compressionQuality: 0.8)
                    #else
                    return nil // macOS handling if needed, but this app is primarily iOS
                    #endif
                }
            } catch {
                print("❌ PhotosAssetLoader: Failed to extract video frame: \(error)")
            }
        }
        
        // Fallback to standard image load (poster frame)
        return await loadImageData(identifier: asset.localIdentifier)
    }
}
