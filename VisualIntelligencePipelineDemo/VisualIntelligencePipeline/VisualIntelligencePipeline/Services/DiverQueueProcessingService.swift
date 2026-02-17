import Foundation
import DiverShared
import DiverKit

#if os(iOS)
import UIKit
#endif
import Photos
import CoreImage
import AVFoundation

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
        // Run on detached task to ensure we don't block calling actor (which might be Main)
        // However, the caller should usually handle the detach. 
        // We'll trust the caller to await this in a non-blocking way, or we can use Task.detached internally if needed.
        // For now, removing @MainActor is the key step.
        
        let records = try queueStore.pendingEntries()
        // If empty, return early
        if records.isEmpty { return }
        
        print("🔄 Queue: Processing \(records.count) pending items...")
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
        // Enforce background context for heavy lifting via Task.detached
        // DiverQueueRecord is Sendable, so we can pass it directly.
        
        try await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            switch record.item.action {
            case "save":
                var descriptor = record.item.descriptor
                
                // 0. Handle Payload (Image Persistence)
                if let payload = record.item.payload {
                    // Determine extension based on descriptor type
                    let fileExtension = descriptor.type == .video ? "mov" : "jpg"
                    
                    if let updated = try? self.persistPayload(payload, for: descriptor, fileExtension: fileExtension) {
                        descriptor = updated
                        
                        // Special handling for Video Payloads: We also need a cover image (thumbnail)
                        if descriptor.type == .video, let videoURL = descriptor.coverImageURL {
                             print("🔄 Processing Service: Generating thumbnail for eager-loaded video...")
                             
                             let scoringService = AestheticsScoringService()

                             var bestFrame: Thumbnail? = nil
                             
                             if let frames = try? await scoringService.extractBestFrames(from: videoURL, count: 1) {
                                bestFrame = frames.first
                             }
                             
                             var thumbnailData: Data?
                             if let best = bestFrame {
                                 #if canImport(UIKit)
                                 let cgImage = best.image
                                 thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
                                 #endif
                             }
                             
                             // Manual save video first
                             let videoFilename = "video_\(descriptor.id).mov"
                             if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                                 let videoLoc = docs.appendingPathComponent("thumbnails", isDirectory: true).appendingPathComponent(videoFilename)
                                 try? payload.write(to: videoLoc)
                                 
                                 // Now save thumbnail as "main" payload
                                 if let thumb = thumbnailData,
                                    let thumbDesc = try? self.persistPayload(thumb, for: descriptor, fileExtension: "jpg", clearIdentifier: true) {
                                     descriptor = thumbDesc
                                     print("✅ Saved Eager Video to \(videoLoc.path)")
                                 }
                             }
                        }
                    }
                } else if let assetID = record.item.photosAssetIdentifier {
                    // 0.5. Hybrid Input: Photos Asset (Deferred Loading)
                    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                    var asset = fetchResult.firstObject
                    
                    // Fallback: Try appending standard suffix if missing (heuristics for raw pickle IDs)
                    if asset == nil && !assetID.contains("/") {
                        let standardID = assetID + "/L0/001"
                        let retryValues = PHAsset.fetchAssets(withLocalIdentifiers: [standardID], options: nil)
                        if let found = retryValues.firstObject {
                            print("🔄 Processing Service: Resolved asset using suffix heuristic: \(standardID)")
                            asset = found
                        }
                    }

                    if let asset = asset {
                        print("🔄 Processing Service: Loading PHAsset \(asset.localIdentifier) type=\(asset.mediaType.rawValue)...")
                        
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
                                // Video Export Succeeded.
                                let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_proc_\(descriptor.id).mov")
                                do {
                                    try data.write(to: tempVideoURL)
                                    
                                    // Extract Best Frame in background
                                    let scoringService = AestheticsScoringService()
                                    var thumbnailData: Data?
                                    
                                    if let frames = try? await scoringService.extractBestFrames(from: tempVideoURL, count: 1),
                                       let best = frames.first {
                                        let cgImage = best.image
                                        #if canImport(UIKit)
                                        thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
                                        #endif
                                        print("✅ Processing Service: Extracted aesthetic thumbnail (score: \(best.score))")
                                    }
                                    
                                    // Fallback
                                    if thumbnailData == nil {
                                         let asset = AVAsset(url: tempVideoURL)
                                         let generator = AVAssetImageGenerator(asset: asset)
                                         generator.appliesPreferredTrackTransform = true
                                         if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                                             #if canImport(UIKit)
                                             thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
                                             #endif
                                         }
                                    }
                                    
                                    if let thumb = thumbnailData,
                                       let updated = try? self.persistPayload(thumb, for: descriptor, fileExtension: "jpg") {
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
                            // --- IMAGE HANDLING ---
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
                                    } else {
                                        // CRITICAL Fix: Handle the case where data is nil but no error is reported (or intermediate callback)
                                        // If this is the final callback (implied by !isDegraded check failing above without data?), 
                                        // or if we just fell through.
                                        // Actually, if data is nil, we should probably fail.
                                        // But requestImageDataAndOrientation might call back with nil data and nil error in rare cases.
                                        print("⚠️ PHImageManager returned nil data and nil error. Leaking continuation prevented.")
                                        resumed = true
                                        continuation.resume(returning: nil)
                                    }
                                }
                            }
                             
                             if let data = imageData {
                                 if let updated = try? self.persistPayload(data, for: descriptor, fileExtension: "jpg") {
                                     descriptor = updated
                                     print("✅ Processing Service: Loaded and persisted PHAsset IMAGE data")
                                 }
                             } else {
                                 print("❌ Processing Service: Failed to load IMAGE data for asset \(assetID)")
                             }
                        }
                    } else {
                        print("❌ Processing Service: Could not find PHAsset with ID \(assetID)")
                    }
                }
                
                // 1. Link Enrichment
                if let linkService = self.linkEnrichmentService, let url = descriptor.urlValue {
                    if let enriched = try? await linkService.enrich(url: url) {
                        descriptor = self.apply(enrichment: enriched, to: descriptor)
                    }
                }
                
                // 2. Context Enrichment
                try await self.cacheStore.store(descriptor: descriptor)
                
                // 3. Handle Attachments
                if let attachments = record.item.attachments, !attachments.isEmpty {
                    print("📸 Processing \(attachments.count) additional session images...")
                    for (index, data) in attachments.enumerated() {
                        let childID = UUID().uuidString
                        let filename = "child_\(childID).jpg"
                        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("thumbnails", isDirectory: true) {
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
                                    masterCaptureID: descriptor.id,
                                    sessionID: descriptor.sessionID,
                                    coverImageURL: fileURL,
                                    placeID: descriptor.placeID,
                                    latitude: descriptor.latitude,
                                    longitude: descriptor.longitude,
                                    purposes: descriptor.purposes
                                )
                                
                                try await self.cacheStore.store(descriptor: childDescriptor)
                                print("✅ Saved child image: \(childID)")
                                
                            } catch {
                                print("❌ Failed to save session attachment \(childID): \(error)")
                            }
                        }
                    }
                }
                
            default:
                print("⚠️ DiverQueueProcessingService: Unknown action '\(record.item.action)' for item \(record.item.id). Skipped.")
                break
            }
        }.value // Wait for the detached task to complete
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
            // FIX: If user pinned a location (placeID exists), preserve it. Otherwise accept enrichment.
            location: descriptor.placeID != nil ? descriptor.location : (enrichment.location ?? descriptor.location),
            price: enrichment.price ?? descriptor.price,
            createdAt: descriptor.createdAt,
            type: descriptor.type,
            attributionID: descriptor.attributionID,
            purpose: descriptor.purpose,
            wrappedLink: descriptor.wrappedLink,
            masterCaptureID: descriptor.masterCaptureID, // FIX: Pass masterCaptureID to persist hierarchy
            photosAssetIdentifier: descriptor.photosAssetIdentifier,
            sessionID: descriptor.sessionID, // FIX: Preserve sessionID
            purposes: descriptor.purposes, // Preserve existing purposes
            processingLog: descriptor.processingLog + ["[\(Date().formatted())] Enriched with Link Metadata"]
        )
    }
}
