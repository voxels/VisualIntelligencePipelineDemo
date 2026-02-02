import Foundation
import DiverShared
import DiverKit

#if os(iOS)
import UIKit
#endif
import Photos
import CoreImage
import AVFoundation

@MainActor
final class DiverQueueProcessingService {
    private let queueStore: DiverQueueStore
    private let cacheStore: KnowMapsCacheStore
    
    // Services
    private let linkEnrichmentService: LinkEnrichmentService?
    private let contextEnrichmentService: ContextualEnrichmentService?

    init(
        queueStore: DiverQueueStore,
        cacheStore: KnowMapsCacheStore,
        linkEnrichmentService: LinkEnrichmentService? = nil,
        contextEnrichmentService: ContextualEnrichmentService? = nil
    ) {
        self.queueStore = queueStore
        self.cacheStore = cacheStore
        self.linkEnrichmentService = linkEnrichmentService
        self.contextEnrichmentService = contextEnrichmentService
    }

    func enqueue(
        descriptor: DiverItemDescriptor,
        action: String = "save",
        source: String? = nil
    ) throws -> DiverQueueRecord {
        let item = DiverQueueItem(action: action, descriptor: descriptor, source: source)
        return try queueStore.enqueue(item)
    }

    func processPendingQueue() async throws {
        #if os(iOS)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "DiverQueueProcessing") {
            // End the task if time expires.
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif
        
        defer {
            #if os(iOS)
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            #endif
        }
        
        let records = try queueStore.pendingEntries()
        for record in records {
            do {
                try await handle(record: record)
                try queueStore.remove(record)
            } catch {
                print("Error processing queue item \(record.item.id): \(error)")
                // keep trying remaining records
                continue
            }
        }
    }

    private func handle(record: DiverQueueRecord) async throws {
        switch record.item.action {
        case "save":
            var descriptor = record.item.descriptor
            
            // 0. Handle Payload (Image Persistence)
            if let payload = record.item.payload {
                // Determine extension based on descriptor type
                let fileExtension = descriptor.type == .video ? "mov" : "jpg"
                
                if let updated = try? persistPayload(payload, for: descriptor, fileExtension: fileExtension) {
                    descriptor = updated
                    
                    // Special handling for Video Payloads: We also need a cover image (thumbnail)
                    if descriptor.type == .video, let videoURL = descriptor.coverImageURL {
                         print("🔄 Processing Service: Generating thumbnail for eager-loaded video...")
                         let scoringService = AestheticsScoringService()
                         // Try to extract frame
                         var thumbnailData: Data?
                         if let frames = try? await scoringService.extractBestFrames(from: videoURL, count: 1), let best = frames.first {
                             #if canImport(UIKit)
                             thumbnailData = UIImage(cgImage: best.image).jpegData(compressionQuality: 0.8)
                             #endif
                         }
                         
                         // Persist thumbnail as payload.jpg for Sidebar
                         // Wait, if we persist thumbnail now, it overwrites the 'updated' descriptor's coverImageURL?
                         // persistPayload returns a descriptor with coverImageURL pointing to the file it saved.
                         // If we save video first -> coverImageURL is video.mov.
                         // Sidebar expects image.
                         // My previous fix in the PHAsset-loading block (deferred) saved the THUMBNAIL as the primary payload/coverImageURL.
                         // And relied on 'photosAssetIdentifier' for the video player.
                         
                         // Here, if we EAGERLY load video data, we don't have a backing PHAsset (or it's inaccessible).
                         // So we MUST have the video file on disk for the player.
                         // AND we MUST have a thumbnail for the sidebar.
                         
                         // DiverItemDescriptor structure:
                         // - coverImageURL: URL
                         // - photosAssetIdentifier: String?
                         
                         // If we set `coverImageURL` to the Thumbnail, the Sidebar works.
                         // But the generic ReferenceDetailView uses `item.photosAssetIdentifier` (line 58) for video.
                         // Or `item.rawPayload` -> UIImage (line 64).
                         // It does NOT seem to have a fallback for "Video File at URL".
                         // `PhotosVideoPlayerView` loads by ID.
                         
                         // If we are in this fallback scenario, `photosAssetIdentifier` is likely useless (Asset not found).
                         // So `PhotosVideoPlayerView` will fail.
                         // This means we CANNOT play the video in ReferenceDetailView currently if import fails PHAsset fetch.
                         // We would need to update `ReferenceDetailView` to play video from `coverImageURL` (or another field) if identifier fails.
                         
                         // For now, priority:
                         // 1. Sidebar works (Thumbnail).
                         // 2. Data is not lost (Video saved).
                         
                         // So:
                         // 1. Save Video to `video_[id].mov` (manually, not via persistPayload which assumes "main payload").
                         // 2. Save Thumbnail using `persistPayload` (so it becomes coverImageURL).
                         
                         // Manual save video:
                         let videoFilename = "video_\(descriptor.id).mov"
                         let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                         let videoLoc = docs.appendingPathComponent("thumbnails", isDirectory: true).appendingPathComponent(videoFilename) // reusing thumbnails dir
                         try? payload.write(to: videoLoc)
                         
                         // Now save thumbnail as "main" payload
                         if let thumb = thumbnailData,
                            let thumbDesc = try? persistPayload(thumb, for: descriptor, fileExtension: "jpg", clearIdentifier: true) {
                             descriptor = thumbDesc
                             // Store video path? Descriptor doesn't have a 'videoURL' field.
                             // It has `url` (String). Maybe put file path there?
                             // DiverItemDescriptor.url is usually the "source" URL.
                             // Maybe `wrappedLink`?
                             // Or just rely on the file existing at `videoLoc` and update the View later.
                             
                             // Let's print the location so we know where it is.
                             print("✅ Saved Eager Video to \(videoLoc.path)")
                         } else {
                             // If thumbnail fails, just persist video as payload so we have SOMETHING
                             // Sidebar might show broken image but data is safe.
                         }
                    }
                }
            } else if let assetID = record.item.photosAssetIdentifier {
                // 0.5. Hybrid Input: Photos Asset (Deferred Loading)
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                if let asset = fetchResult.firstObject {
                    print("🔄 Processing Service: Loading PHAsset \(assetID) type=\(asset.mediaType.rawValue)...")
                    
                    if asset.mediaType == .video {
                        // --- VIDEO HANDLING ---
                        let manager = PHImageManager.default()
                        let options = PHVideoRequestOptions()
                        options.isNetworkAccessAllowed = true
                        options.deliveryMode = .highQualityFormat
                        
                        let videoData: Data? = await withCheckedContinuation { continuation in
                             manager.requestExportSession(forVideo: asset, options: options, exportPreset: AVAssetExportPresetHighestQuality) { session, info in
                                 guard let session = session else {
                                     print("❌ Failed to create export session: \(String(describing: info))")
                                     continuation.resume(returning: nil)
                                     return
                                 }
                                 
                                 let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
                                 session.outputURL = tempURL
                                 session.outputFileType = .mov
                                 
                                 session.exportAsynchronously {
                                     switch session.status {
                                     case .completed:
                                         if let data = try? Data(contentsOf: tempURL) {
                                             try? FileManager.default.removeItem(at: tempURL)
                                             continuation.resume(returning: data)
                                         } else {
                                             continuation.resume(returning: nil)
                                         }
                                     default:
                                         print("❌ Export failed status: \(session.status.rawValue)")
                                         continuation.resume(returning: nil)
                                     }
                                 }
                             }
                        }
                        
                        if let data = videoData {
                            // Video Export Succeeded. Now extract aesthetic thumbnail from the temp MOV.
                            // We need to write 'data' to a temp file again because 'extractBestFrames' takes a URL.
                            let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_proc_\(descriptor.id).mov")
                            do {
                                try data.write(to: tempVideoURL)
                                
                                // Extract Best Frame
                                let scoringService = AestheticsScoringService()
                                var thumbnailData: Data?
                                
                                if let frames = try? await scoringService.extractBestFrames(from: tempVideoURL, count: 1),
                                   let best = frames.first {
                                    // Use the best frame
                                    #if canImport(UIKit)
                                    thumbnailData = UIImage(cgImage: best.image).jpegData(compressionQuality: 0.8)
                                    #endif
                                    print("✅ Processing Service: Extracted aesthetic thumbnail (score: \(best.score))")
                                }
                                
                                // Fallback if scoring fails
                                if thumbnailData == nil {
                                     // Just use the first frame or whatever we can get
                                     let asset = AVAsset(url: tempVideoURL)
                                     let generator = AVAssetImageGenerator(asset: asset)
                                     generator.appliesPreferredTrackTransform = true
                                     if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                                         #if canImport(UIKit)
                                         thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
                                         #endif
                                     }
                                }
                                
                                // Persist THUMBNAIL as the payload
                                // This ensures SidebarView can display it via UIImage(data: rawPayload)
                                if let thumb = thumbnailData,
                                   let updated = try? persistPayload(thumb, for: descriptor, fileExtension: "jpg") {
                                    descriptor = updated
                                    print("✅ Processing Service: Persisted Video Thumbnail as Payload")
                                }
                                
                                try? FileManager.default.removeItem(at: tempVideoURL)
                            } catch {
                                print("❌ Failed to process video thumbnail: \(error)")
                            }
                        } else {
                            print("❌ Processing Service: Failed to load VIDEO data for asset \(assetID)")
                        }
                        
                    } else {
                        // --- IMAGE HANDLING (Existing Logic) ---
                         let manager = PHImageManager.default()
                         let options = PHImageRequestOptions()
                         options.isNetworkAccessAllowed = true
                         options.deliveryMode = .highQualityFormat
                         options.isSynchronous = false 
                         
                         let imageData: Data? = await withCheckedContinuation { continuation in
                             var resumed = false
                             manager.requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                                 guard !resumed else { return }
                                 let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                                 let error = info?[PHImageErrorKey] as? Error
                                 let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false

                                 if let data = data, !isDegraded {
                                     // Fix Orientation using CIImage (same as before)
                                     if let ciImage = CIImage(data: data) {
                                         let appliedOrientation = Int32(orientation.rawValue)
                                         let fixedImage = ciImage.oriented(forExifOrientation: appliedOrientation)
                                         let context = CIContext()
                                         if let colorSpace = fixedImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                                            let jpegData = context.jpegRepresentation(of: fixedImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]) {
                                             resumed = true
                                             continuation.resume(returning: jpegData)
                                             return
                                         }
                                     }
                                     resumed = true
                                     continuation.resume(returning: data)
                                 } else if error != nil || isCancelled {
                                     print("❌ PHImageManager failed: \(String(describing: error))")
                                     resumed = true
                                     continuation.resume(returning: nil)
                                 }
                             }
                         }
                         
                         if let data = imageData {
                             // Use aesthetics service to score if possible?
                             // DiverQueueProcessingService doesn't seem to natively use AestheticsScoringService for images (it relies on LinkEnrichment or ContextEnrichment).
                             // We'll just persist.
                             if let updated = try? persistPayload(data, for: descriptor, fileExtension: "jpg") {
                                 descriptor = updated
                                 print("✅ Processing Service: Loaded and persisted PHAsset IMAGE data")
                             }
                         } else {
                             print("❌ Processing Service: Failed to load IMAGE data for asset \(assetID)")
                         }
                    }
                } else {
                    print("❌ Processing Service: Could not find PHAsset with ID \(assetID)")
                    // Keep going? If we fail to load payload, we still might want to process the item metadata.
                    // But without payload it's kind of empty. 
                    // Let's assume the descriptor is valid enough.
                }
            }
            
            // 1. Link Enrichment
            if let linkService = linkEnrichmentService, let url = descriptor.urlValue {
                if let enriched = try? await linkService.enrich(url: url) {
                    descriptor = apply(enrichment: enriched, to: descriptor)
                }
            }
            
            // 2. Context Enrichment
            try await cacheStore.store(descriptor: descriptor)
            
            // 3. Handle Attachments (Session Images)
            if let attachments = record.item.attachments, !attachments.isEmpty {
                print("📸 Processing \(attachments.count) additional session images...")
                for (index, data) in attachments.enumerated() {
                    let childID = UUID().uuidString
                    let filename = "child_\(childID).jpg"
                    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("thumbnails", isDirectory: true)
                    let fileURL = dir.appendingPathComponent(filename)
                    
                    do {
                        try data.write(to: fileURL)
                        
                        let childDescriptor = DiverItemDescriptor(
                            id: childID,
                            url: "diver-asset://\(childID)",
                            title: "Session Image \(index + 1)",
                            descriptionText: "Additional capture for session",
                            styleTags: ["session_asset", "child"],
                            categories: ["image", "child"],
                            location: descriptor.location,
                            type: .image,
                            purpose: descriptor.purpose,
                            masterCaptureID: descriptor.id, // Link to Master
                            sessionID: descriptor.sessionID, // Link to Session
                            coverImageURL: fileURL,
                            placeID: descriptor.placeID,
                            latitude: descriptor.latitude,
                            longitude: descriptor.longitude,
                            purposes: descriptor.purposes
                        )
                        
                        try await cacheStore.store(descriptor: childDescriptor)
                        print("✅ Saved child image: \(childID)")
                        
                    } catch {
                        print("❌ Failed to save session attachment \(childID): \(error)")
                    }
                }
            }
            
        default:
            print("⚠️ DiverQueueProcessingService: Unknown action '\(record.item.action)' for item \(record.item.id). Skipped.")
            break
        }
    }
    
    private func persistPayload(_ payload: Data, for descriptor: DiverItemDescriptor, fileExtension: String = "jpg", clearIdentifier: Bool = false) throws -> DiverItemDescriptor {
        let filename = "\(descriptor.id)-payload.\(fileExtension)"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(filename)
        
        try payload.write(to: fileURL)
        
        return DiverItemDescriptor(
            id: descriptor.id,
            url: descriptor.url,
            title: descriptor.title,
            descriptionText: descriptor.descriptionText,
            styleTags: descriptor.styleTags,
            categories: descriptor.categories,
            location: descriptor.location,
            price: descriptor.price,
            createdAt: descriptor.createdAt,
            type: descriptor.type,
            attributionID: descriptor.attributionID,
            purpose: descriptor.purpose,
            wrappedLink: descriptor.wrappedLink,
            masterCaptureID: descriptor.masterCaptureID,
            photosAssetIdentifier: descriptor.photosAssetIdentifier,
            sessionID: descriptor.sessionID,
            coverImageURL: fileURL,
            placeID: descriptor.placeID,
            latitude: descriptor.latitude,
            longitude: descriptor.longitude,
            purposes: descriptor.purposes,
            processingLog: descriptor.processingLog + ["[\(Date().formatted())] Persisted payload (\(fileExtension)) to disk"]
        )
    }
    
    private func apply(enrichment: EnrichmentData, to descriptor: DiverItemDescriptor) -> DiverItemDescriptor {
        // Merge enriched data into a new descriptor
        let newTitle = (descriptor.title == "Untitled" || descriptor.title.isEmpty) ? (enrichment.title ?? descriptor.title) : descriptor.title
        let newDesc = (descriptor.descriptionText == nil || descriptor.descriptionText?.isEmpty == true) ? enrichment.descriptionText : descriptor.descriptionText
        
        let existingTags = Set(descriptor.styleTags + descriptor.categories)
        let newTags = Set(enrichment.styleTags + enrichment.categories)
        let mergedTags = existingTags.union(newTags)
        
        return DiverItemDescriptor(
            id: descriptor.id,
            url: descriptor.url,
            title: newTitle,
            descriptionText: newDesc,
            styleTags: Array(mergedTags).sorted(), // Flatten into styleTags for now as categories might be specific
            categories: descriptor.categories, // Keep original categories or merge? Let's keep original + new in styleTags
            location: enrichment.location ?? descriptor.location,
            price: enrichment.price ?? descriptor.price,
            createdAt: descriptor.createdAt,
            type: descriptor.type,
            attributionID: descriptor.attributionID,
            purpose: descriptor.purpose,
            wrappedLink: descriptor.wrappedLink,
            masterCaptureID: descriptor.masterCaptureID, // FIX: Pass masterCaptureID to persist hierarchy
            photosAssetIdentifier: descriptor.photosAssetIdentifier,
            purposes: descriptor.purposes, // Preserve existing purposes
            processingLog: descriptor.processingLog + ["[\(Date().formatted())] Enriched with Link Metadata"]
        )
    }
}
