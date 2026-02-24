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
import ImageIO
import Vision

/// A `Transferable`-conforming wrapper for picker images.
/// Handles JPEG, PNG, HEIC, and TIFF content types that the picker may provide.
struct TransferableImage: Transferable {
    let data: Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { data in
            TransferableImage(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            TransferableImage(data: data)
        }
        DataRepresentation(importedContentType: .heic) { data in
            TransferableImage(data: data)
        }
        DataRepresentation(importedContentType: .tiff) { data in
            TransferableImage(data: data)
        }
    }
}

/// Service for importing photos and videos from the user's library.
/// Handles batch processing, metadata extraction, clustering, and persistence.
@MainActor
public final class PhotoLibraryImportService {
    
    private let clusteringService = SessionClusteringService()
    private let geocodingService: ReverseGeocodingService
    private let modelContext: ModelContext
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.geocodingService = ReverseGeocodingService()
    }
    
    // MARK: - Public API
    
    /// Import selected photos/videos into a new collection.
    /// - Parameters:
    ///   - items: PhotosPickerItems from multi-select picker
    ///   - collectionName: Name for the new collection
    /// - Returns: Created SessionCollection
    @MainActor
    public func importItems(
        _ items: [PhotosPickerItem],
        collectionName: String
    ) async throws -> SessionCollection {
        print("📥 PhotoLibraryImportService: Starting import of \(items.count) items...")
        
        // 1. Create collection
        let collection = SessionCollection(name: collectionName)
        modelContext.insert(collection)
        
        // 2. Extract metadata from items OFF the main thread to keep UI responsive
        let capturedItems = items
        let importedAssets: [ImportedAsset] = await Task.detached(priority: .userInitiated) {
            var assets: [ImportedAsset] = []
            let batchSize = 10
            
            for batchStart in stride(from: 0, to: capturedItems.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, capturedItems.count)
                let batch = Array(capturedItems[batchStart..<batchEnd])
                
                // Process batch sequentially - memory released after each await
                for item in batch {
                    if let asset = await self.extractAssetMetadataOnly(from: item) {
                        assets.append(asset)
                    }
                }
                
                print("📥 Processed batch \(batchStart/batchSize + 1)/\((capturedItems.count + batchSize - 1)/batchSize)")
            }
            
            return assets
        }.value
        
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
                // Check semantic location (Home/Work) first
                if let semanticName = await determineSemanticLocation(for: coord) {
                    locationName = semanticName
                    // Still lookup place context for details, but we already have a strong name
                    placeContext = await geocodingService.lookup(coordinate: coord)
                } else {
                    placeContext = await geocodingService.lookup(coordinate: coord)
                    locationName = placeContext?.name
                }
                
                placeID = placeContext?.placeID
            }
            
            // Create session
            let session = SessionMetadata(
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
                    rawPayload: asset.data.isEmpty ? nil : asset.data, // use eager data if present, otherwise nil (on-demand)
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

    /// Import selected photos/videos into an EXISTING session.
    /// - Parameters:
    ///   - items: PhotosPickerItems from multi-select picker
    ///   - session: The existing SessionMetadata to import into
    /// - Returns: List of created ProcessedItems
    @MainActor
    public func importItems(
        _ items: [PhotosPickerItem],
        into session: SessionMetadata
    ) async throws -> [ProcessedItem] {
        print("📥 PhotoLibraryImportService: Starting import of \(items.count) items into session '\(session.displayTitle)'...")
        
        // 1. Extract metadata from items
        var importedAssets: [ImportedAsset] = []
        let batchSize = 10
        
        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let batch = Array(items[batchStart..<batchEnd])
            
            for item in batch {
                if let asset = await extractAssetMetadataOnly(from: item) {
                    importedAssets.append(asset)
                }
            }
        }
        
        // 2. Create ProcessedItems directly for this session
        var newItems: [ProcessedItem] = []
        var assetToPhotoItem: [String: PhotosPickerItem] = [:]
        
        for (index, item) in items.enumerated() {
            if index < importedAssets.count {
                assetToPhotoItem[importedAssets[index].id] = item
            }
        }
        
        for asset in importedAssets {
            let item = ProcessedItem(
                id: asset.id,
                createdAt: asset.creationDate ?? Date(),
                rawPayload: asset.data.isEmpty ? nil : asset.data,
                status: .queued,
                source: "photoLibraryImport",
                sessionID: session.sessionID, // Explicitly assign to target session
                mediaType: asset.isVideo ? "video" : (asset.isScreenshot ? "screenshot" : "image"),
                filename: asset.originalFilename,
                photosAssetIdentifier: asset.photosItemIdentifier
            )
            item.session = session // Set relationship
            
            // Set location if available (don't override session location, just item)
            if let loc = asset.location {
                item.location = "\(loc.latitude),\(loc.longitude)"
                // Try to geocode individual item
                if let itemPlace = await geocodingService.lookup(coordinate: loc) {
                    item.placeContext = itemPlace
                }
            }
            
            modelContext.insert(item)
            newItems.append(item)
        }
        
        // 3. Update session timestamp
        session.updatedAt = Date()
        try modelContext.save()
        
        // 4. Extract thumbnail if session has none
        if (session.thumbnailPaths.isEmpty), let firstAsset = importedAssets.first, let photoItem = assetToPhotoItem[firstAsset.id] {
            Task.detached(priority: .background) {
                await self.extractThumbnailForSession(asset: firstAsset, photoItem: photoItem)
            }
        }
        
        // 5. Enqueue items
        Task.detached(priority: .background) {
            await self.enqueueItemsToProcessingQueue(
                assets: importedAssets,
                assetToPhotoItem: assetToPhotoItem
            )
        }
        
        print("✅ Added \(newItems.count) items to session '\(session.displayTitle)'")
        return newItems
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
                    photosAssetIdentifier: asset.photosItemIdentifier, // Pass identifier so it persists!
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
                    payload: asset.data.isEmpty ? nil : asset.data, // Check if we eagerly loaded data
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
    
    private nonisolated func saveThumbnailToDisk(image: CGImage, id: String) -> String? {
        #if canImport(UIKit)
        // Draw into an opaque context to strip alpha channel —
        // JPEG doesn't support alpha and keeping it doubles decode memory.
        let size = CGSize(width: image.width, height: image.height)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.opaque = true
            return fmt
        }())
        let opaqueImage = renderer.image { ctx in
            ctx.cgContext.draw(image, in: CGRect(origin: .zero, size: size))
        }
        return saveThumbnailToDisk(image: opaqueImage, id: id)
        #else
        return nil
        #endif
    }
    
    #if canImport(UIKit)
    private nonisolated func saveThumbnailToDisk(image: UIImage, id: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        // Ensure directory exists
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
    }
    #endif
    
    private func fetchProcessedItem(assetID: String) -> ProcessedItem? {
        let id = assetID
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    private func updateSession(sessionID: String, thumbnailPaths: [String]) async {
        let id = sessionID
        let descriptor = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate { $0.sessionID == id }
        )
        
        if let session = try? modelContext.fetch(descriptor).first {
            session.thumbnailPaths = thumbnailPaths
            session.updatedAt = Date()
            do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (session thumbnail update): \(error)") }
            print("✅ Updated session \(sessionID) with \(thumbnailPaths.count) thumbnails")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Extract metadata ONLY from a PhotosPickerItem - does NOT load full image data
    /// Uses PHAsset for reliable creation date and location (works for both photos and videos)
    /// Runs off the main actor to keep UI responsive.
    private nonisolated func extractAssetMetadataOnly(from item: PhotosPickerItem) async -> ImportedAsset? {
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
        
        // Fetch PHAsset using the identifier (includes /L0/001 heuristic)
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
            // Fallback: PHAsset not found (e.g. Limited Access). Eagerly load full data.
            print("⚠️ PHAsset not found for \(itemIdentifier). Falling back to eager data loading.")
            
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    // Attempt to read EXIF/Metadata from the data
                    if !isVideo {
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
                    
                    // Return with DATA populated
                    print("✅ Eager loaded \(data.count) bytes for \(itemIdentifier)")
                    return ImportedAsset(
                        id: UUID().uuidString,
                        data: data,
                        isVideo: isVideo,
                        isScreenshot: isScreenshot,
                        isScreenRecording: isScreenRecording,
                        creationDate: creationDate,
                        location: location,
                        originalFilename: originalFilename,
                        photosItemIdentifier: itemIdentifier
                    )
                }
            } catch {
                print("❌ Failed to eagerly load data for \(itemIdentifier): \(error)")
            }
        }
        
        // Return asset with minimal data - deferred loading via photosItemIdentifier
        // ALWAYS return an asset (never nil) so downstream can use deferred PHAsset loading
        return ImportedAsset(
            id: UUID().uuidString,
            data: Data(), // Empty data - deferred loading from PHAsset downstream
            isVideo: isVideo,
            isScreenshot: isScreenshot,
            isScreenRecording: isScreenRecording,
            creationDate: creationDate,
            location: location,
            originalFilename: originalFilename,
            photosItemIdentifier: itemIdentifier
        )
    }
    
    /// Fetch PHAsset from Photos library using its local identifier
    private nonisolated func fetchPHAsset(identifier: String) -> PHAsset? {
        // 1. Try exact match
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        if let asset = fetchResult.firstObject {
            return asset
        }
        
        // 2. Try appending standard suffix if missing (sometimes Picker returns raw UUID)
        if !identifier.contains("/") {
            let standardID = identifier + "/L0/001"
            let retryResult = PHAsset.fetchAssets(withLocalIdentifiers: [standardID], options: nil)
            if let asset = retryResult.firstObject {
                print("🔄 PhotoLibraryImportService: Found PHAsset using suffix heuristic: \(standardID)")
                return asset
            }
        }
        
        return nil
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
                        let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try? handler.perform([aestheticsRequest])
                        if let score = aestheticsRequest.results?.first?.overallScore {
                            processedItem.aestheticsScore = Double(score)
                        }
                    }
                    #endif
                    
                    if let thumbnail = createDownsampledThumbnail(from: data, id: asset.id) {
                        thumbnailPaths.append(thumbnail)
                    }
                }
                
                // Save the aesthetics score
                do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (aesthetics score): \(error)") }
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
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)
        
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        let fileURL: String? = await withUnsafeContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { [weak self] cgImage, _, error in
                if let error {
                    print("⚠️ Failed to extract video frame: \(error)")
                    continuation.resume(returning: nil)
                } else if let cgImage, let self {
                    let path = self.saveThumbnailToDisk(image: cgImage, id: id)
                    continuation.resume(returning: path)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        return fileURL
    }
    
    /// Create a memory-efficient downsampled thumbnail from image data
    private func createDownsampledThumbnail(from data: Data, id: String) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        
        // 1. Get Orientation from Properties
        var orientation: CGImagePropertyOrientation = .up
        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
           let rawOrientation = properties[kCGImagePropertyOrientation as String] as? UInt32,
           let cgOrientation = CGImagePropertyOrientation(rawValue: rawOrientation) {
            orientation = cgOrientation
        }
        
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: false, // Do NOT transform, we handle it via UIImage to bake it correctly
            kCGImageSourceThumbnailMaxPixelSize: 300,
            kCGImageSourceShouldCacheImmediately: false
        ]
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        
        #if canImport(UIKit)
        // Convert to UIImage with correct orientation
        let uiOrientation = UIImage.Orientation(rawValue: Int(orientation.rawValue))
        let uiImage = UIImage(cgImage: downsampledImage, scale: 1.0, orientation: uiOrientation ?? .up)
        return saveThumbnailToDisk(image: uiImage, id: id)
        #else
        // Fallback for macOS (if needed later)
        return saveThumbnailToDisk(image: downsampledImage, id: id)
        #endif
    }
    
    /// Check if the coordinate corresponds to Home or Work
    private func determineSemanticLocation(for coordinate: CLLocationCoordinate2D) async -> String? {
        let contactService = ContactService()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Fetch locations concurrently
        // Note: checking permissions implicitly via ContactService
        
        do {
            async let homeLoc = contactService.getHomeLocation()
            async let workLoc = contactService.getWorkLocation()
            
            let (home, work) = try await (homeLoc, workLoc)
            
            if let home = home, location.distance(from: home) < 300 { // 300m threshold
                return "Home"
            }
            if let work = work, location.distance(from: work) < 300 {
                return "Work"
            }
        } catch {
            print("⚠️ Semantic location check failed: \(error)")
        }
        
        return nil
    }
    
    /// Legacy method - kept for backward compatibility
    private func extractAsset(from item: PhotosPickerItem) async -> ImportedAsset? {
        return await extractAssetMetadataOnly(from: item)
    }
}
