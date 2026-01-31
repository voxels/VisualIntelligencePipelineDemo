import Foundation
import PhotosUI
import Photos
import SwiftUI
import CoreLocation
import SwiftData
import DiverShared
import UniformTypeIdentifiers
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

/// Service for importing photos and videos from the user's library.
/// Handles batch processing, metadata extraction, clustering, and persistence.
@MainActor
public final class PhotoLibraryImportService {
    
    private let clusteringService = SessionClusteringService()
    private let geocodingService: ReverseGeocodingService
    private let modelContext: ModelContext
    
    public init(modelContext: ModelContext, foursquareService: ContextualEnrichmentService? = nil) {
        self.modelContext = modelContext
        self.geocodingService = ReverseGeocodingService(foursquareService: foursquareService)
    }
    
    // MARK: - Public API
    
    /// Import selected photos/videos into a new collection.
    /// - Parameters:
    ///   - items: PhotosPickerItems from multi-select picker
    ///   - collectionName: Name for the new collection
    /// - Returns: Created DiverCollection
    @MainActor
    public func importItems(
        _ items: [PhotosPickerItem],
        collectionName: String
    ) async throws -> DiverCollection {
        print("📥 PhotoLibraryImportService: Starting import of \(items.count) items...")
        
        // 1. Create collection
        let collection = DiverCollection(name: collectionName)
        modelContext.insert(collection)
        
        // 2. Extract metadata from items IN BATCHES to avoid memory pressure
        var importedAssets: [ImportedAsset] = []
        let batchSize = 10
        
        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let batch = Array(items[batchStart..<batchEnd])
            
            // Process batch sequentially - memory released after each await
            for item in batch {
                if let asset = await extractAssetMetadataOnly(from: item) {
                    importedAssets.append(asset)
                }
            }
            
            print("📥 Processed batch \(batchStart/batchSize + 1)/\((items.count + batchSize - 1)/batchSize)")
        }
        
        print("📥 Extracted \(importedAssets.count) assets from \(items.count) items")
        
        // 3. Cluster into sessions (metadata only, no image data)
        let clusters = clusteringService.clusterItems(importedAssets)
        
        // 4. Create sessions and process items
        var sessionIDs: [String] = []
        var assetToPhotoItem: [String: PhotosPickerItem] = [:]
        
        // Map asset IDs to PhotosPickerItems for later thumbnail extraction
        for (index, item) in items.enumerated() {
            if index < importedAssets.count {
                assetToPhotoItem[importedAssets[index].id] = item
            }
        }
        
        for cluster in clusters {
            let (sessionID, timestamp, location) = clusteringService.generateSessionMetadata(
                from: cluster,
                collectionID: collection.collectionID
            )
            
            // Reverse geocode location
            var placeContext: PlaceContext?
            var locationName: String?
            var placeID: String?
            
            if let coord = location {
                placeContext = await geocodingService.lookup(coordinate: coord)
                locationName = placeContext?.name
                placeID = placeContext?.placeID
            }
            
            // Create session
            let session = DiverSession(
                sessionID: sessionID,
                title: locationName ?? "Session \(sessionIDs.count + 1)",
                createdAt: timestamp,
                updatedAt: timestamp,
                latitude: location?.latitude,
                longitude: location?.longitude,
                placeID: placeID,
                locationName: locationName,
                collectionID: collection.collectionID
            )
            modelContext.insert(session)
            sessionIDs.append(sessionID)
            
            // Create ProcessedItems for each asset in the cluster
            for asset in cluster {
                let item = ProcessedItem(
                    id: asset.id,
                    createdAt: asset.creationDate ?? Date(),
                    rawPayload: nil, // Don't store full media data - load on-demand via photosAssetIdentifier
                    status: .queued, // Queue for processing - data loaded on-demand from PHAsset
                    source: "photoLibraryImport",
                    sessionID: sessionID,
                    mediaType: asset.isVideo ? "video" : (asset.isScreenshot ? "screenshot" : "image"),
                    filename: asset.originalFilename,
                    photosAssetIdentifier: asset.photosItemIdentifier // Store for on-demand data loading
                )
                
                // Set location if available
                if let loc = asset.location {
                    item.location = "\(loc.latitude),\(loc.longitude)"
                    if placeContext == nil {
                        // Try to geocode individual item location
                        if let itemPlace = await geocodingService.lookup(coordinate: loc) {
                            item.placeContext = itemPlace
                        }
                    } else {
                        item.placeContext = placeContext
                    }
                }
                
                modelContext.insert(item)
            }
        }
        
        // 5. Update collection with session IDs
        collection.sessionIDs = sessionIDs
        collection.updatedAt = Date()
        
        try modelContext.save()
        
        // 6. Extract thumbnails for sessions in background (loads on-demand from PHAsset)
        Task.detached(priority: .background) {
            for cluster in clusters {
                // Get representative asset for thumbnail
                if let firstAsset = cluster.first,
                   let photoItem = assetToPhotoItem[firstAsset.id] {
                    await self.extractThumbnailForSession(asset: firstAsset, photoItem: photoItem)
                }
            }
        }
        
        // 7. Enqueue items to DiverQueueStore for pipeline processing (uses asset reference, not payload data)
        Task.detached(priority: .background) {
            await self.enqueueItemsToProcessingQueue(
                assets: importedAssets,
                assetToPhotoItem: assetToPhotoItem
            )
        }
        
        print("✅ PhotoLibraryImportService: Created collection '\(collectionName)' with \(sessionIDs.count) sessions")
        
        return collection
    }
    
    /// Enqueue imported items to DiverQueueStore for full pipeline processing.
    /// Uses photosAssetIdentifier instead of loading full payload data to avoid memory crashes.
    private func enqueueItemsToProcessingQueue(
        assets: [ImportedAsset],
        assetToPhotoItem: [String: PhotosPickerItem]
    ) async {
        guard let queueDirectory = AppGroupContainer.queueDirectoryURL() else {
            print("❌ PhotoLibraryImportService: Cannot get queue directory")
            return
        }
        
        do {
            let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
            var enqueuedCount = 0
            
            // Enqueue items with photosAssetIdentifier (no payload data loaded)
            for asset in assets {
                // Create descriptor
                let descriptor = DiverItemDescriptor(
                    id: asset.id,
                    url: "",
                    title: asset.originalFilename ?? "Photo Import",
                    descriptionText: nil,
                    styleTags: [],
                    categories: ["photo_import"],
                    location: asset.location.map { "\($0.latitude),\($0.longitude)" },
                    price: nil,
                    type: asset.isVideo ? .video : .image,
                    attributionID: nil,
                    masterCaptureID: nil,
                    sessionID: fetchProcessedItem(assetID: asset.id)?.sessionID,
                    purposes: []
                )
                
                // Create queue item with photosAssetIdentifier (NO payload - loaded on-demand during processing)
                let queueItem = DiverQueueItem(
                    id: UUID(),
                    action: "save",
                    descriptor: descriptor,
                    source: "photoLibraryImport",
                    createdAt: asset.creationDate ?? Date(),
                    payload: nil, // Don't load data - use photosAssetIdentifier instead
                    photosAssetIdentifier: asset.photosItemIdentifier
                )
                
                _ = try queueStore.enqueue(queueItem)
                enqueuedCount += 1
            }
            
            print("✅ PhotoLibraryImportService: Enqueued \(enqueuedCount) items with PHAsset references for processing")
            
        } catch {
            print("❌ PhotoLibraryImportService: Failed to enqueue items: \(error)")
        }
    }
    
    // MARK: - Thumbnail Extraction
    
    private func saveThumbnailToDisk(image: CGImage, id: String) -> String? {
        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: image)
        guard let data = uiImage.jpegData(compressionQuality: 0.8) else { return nil }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("thumbnails", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let filename = "\(id)-thumb.jpg"
            let fileURL = dir.appendingPathComponent(filename)
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            print("⚠️ Failed to save thumbnail: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
    
    private func fetchProcessedItem(assetID: String) -> ProcessedItem? {
        let id = assetID
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    private func updateSession(sessionID: String, thumbnailPaths: [String]) async {
        let id = sessionID
        let descriptor = FetchDescriptor<DiverSession>(
            predicate: #Predicate { $0.sessionID == id }
        )
        
        if let session = try? modelContext.fetch(descriptor).first {
            session.thumbnailPaths = thumbnailPaths
            session.updatedAt = Date()
            try? modelContext.save()
            print("✅ Updated session \(sessionID) with \(thumbnailPaths.count) thumbnails")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Extract metadata ONLY from a PhotosPickerItem - does NOT load full image data
    /// Uses PHAsset for reliable creation date and location (works for both photos and videos)
    private func extractAssetMetadataOnly(from item: PhotosPickerItem) async -> ImportedAsset? {
        // Detect media type from content types (no data loading needed)
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        let isScreenshot = item.supportedContentTypes.contains { 
            $0.identifier.contains("screenshot") || $0.identifier.contains("public.png") 
        }
        let isScreenRecording = item.supportedContentTypes.contains { 
            $0.identifier.contains("screen") && $0.conforms(to: .movie) 
        }
        
        // Get the item identifier for later reference
        let itemIdentifier = item.itemIdentifier ?? UUID().uuidString
        
        // Try to get metadata from PHAsset (most reliable for both photos and videos)
        var creationDate: Date?
        var location: CLLocationCoordinate2D?
        var originalFilename: String?
        
        // Fetch PHAsset using the identifier
        if let phAsset = fetchPHAsset(identifier: itemIdentifier) {
            creationDate = phAsset.creationDate
            if let assetLocation = phAsset.location?.coordinate {
                location = assetLocation
            }
            // Get original filename from resources
            let resources = PHAssetResource.assetResources(for: phAsset)
            originalFilename = resources.first?.originalFilename
            print("📷 Extracted PHAsset metadata: date=\(creationDate?.formatted() ?? "nil"), location=\(location?.latitude ?? 0),\(location?.longitude ?? 0)")
        } else {
            // Fallback: try EXIF for images if PHAsset not available
            if !isVideo {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        if let source = CGImageSourceCreateWithData(data as CFData, nil),
                           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                            
                            // Extract date from EXIF
                            if let exif = properties["{Exif}"] as? [String: Any],
                               let dateString = exif["DateTimeOriginal"] as? String {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                creationDate = formatter.date(from: dateString)
                            }
                            
                            // Extract GPS from EXIF
                            if let gps = properties["{GPS}"] as? [String: Any],
                               let lat = gps["Latitude"] as? Double,
                               let lon = gps["Longitude"] as? Double,
                               let latRef = gps["LatitudeRef"] as? String,
                               let lonRef = gps["LongitudeRef"] as? String {
                                let latitude = latRef == "S" ? -lat : lat
                                let longitude = lonRef == "W" ? -lon : lon
                                location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                            }
                        }
                    }
                } catch {
                    print("⚠️ Error extracting EXIF: \(error)")
                }
            }
        }
        
        // Return asset with minimal data - just metadata and identifier
        return ImportedAsset(
            id: UUID().uuidString,
            data: Data(), // Empty data - we'll use itemIdentifier to fetch when needed
            isVideo: isVideo,
            isScreenshot: isScreenshot,
            isScreenRecording: isScreenRecording,
            creationDate: creationDate,
            location: location,
            originalFilename: originalFilename,
            photosItemIdentifier: itemIdentifier // Store for later retrieval
        )
    }
    
    /// Fetch PHAsset from Photos library using its local identifier
    private func fetchPHAsset(identifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return fetchResult.firstObject
    }
    
    /// Extract thumbnail for a single session's first asset - loads data on-demand
    private func extractThumbnailForSession(asset: ImportedAsset, photoItem: PhotosPickerItem) async {
        guard let processedItem = fetchProcessedItem(assetID: asset.id),
              let sessionID = processedItem.sessionID else {
            return
        }
        
        var thumbnailPaths: [String] = []
        let aestheticsService = AestheticsScoringService()
        
        // Load data on-demand for this single item only
        do {
            if let data = try await photoItem.loadTransferable(type: Data.self) {
                if asset.isVideo {
                    // Video: Write to temp file and extract frame
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(asset.id).mov")
                    try data.write(to: tempURL)
                    
                    // Extract best frames with aesthetics scoring
                    if let frames = try? await aestheticsService.extractBestFrames(from: tempURL, count: 1),
                       let bestFrame = frames.first {
                        if let thumbnail = saveThumbnailToDisk(image: bestFrame.image, id: asset.id) {
                            thumbnailPaths.append(thumbnail)
                        }
                        // Store aesthetics score (score is a Float)
                        processedItem.aestheticsScore = Double(bestFrame.score)
                    } else if let thumbnail = await extractSingleVideoThumbnail(from: tempURL, id: asset.id) {
                        thumbnailPaths.append(thumbnail)
                    }
                    
                    try? FileManager.default.removeItem(at: tempURL)
                } else {
                    // Image: Score and create thumbnail
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage {
                        if let score = try? await aestheticsService.scoreImage(cgImage) {
                            processedItem.aestheticsScore = Double(score)
                        }
                    }
                    #endif
                    
                    if let thumbnail = createDownsampledThumbnail(from: data, id: asset.id) {
                        thumbnailPaths.append(thumbnail)
                    }
                }
                
                // Save the aesthetics score
                try? modelContext.save()
            }
        } catch {
            DiverLogger.pipeline.error("Failed to extract thumbnail for session: \(error)")
        }
        
        if !thumbnailPaths.isEmpty {
            await updateSession(sessionID: sessionID, thumbnailPaths: thumbnailPaths)
        }
    }
    
    /// Extract a single thumbnail frame from video using AVAssetImageGenerator
    private func extractSingleVideoThumbnail(from url: URL, id: String) async -> String? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)
        
        do {
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return saveThumbnailToDisk(image: cgImage, id: id)
        } catch {
            print("⚠️ Failed to extract video frame: \(error)")
            return nil
        }
    }
    
    /// Create a memory-efficient downsampled thumbnail from image data
    private func createDownsampledThumbnail(from data: Data, id: String) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
            kCGImageSourceShouldCacheImmediately: false
        ]
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        
        return saveThumbnailToDisk(image: downsampledImage, id: id)
    }
    
    /// Legacy method - kept for backward compatibility
    private func extractAsset(from item: PhotosPickerItem) async -> ImportedAsset? {
        return await extractAssetMetadataOnly(from: item)
    }
}
