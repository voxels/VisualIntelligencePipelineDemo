import Foundation
import DiverShared
import DiverKit

#if os(iOS)
import UIKit
#endif

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
                // If we have a payload, save it to disk and assume it's the cover image (or main content)
                let filename = "\(descriptor.id)-payload.jpg" // Assume JPG for now, or match payload type if known
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dir = docs.appendingPathComponent("thumbnails", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let fileURL = dir.appendingPathComponent(filename)
                
                do {
                    try payload.write(to: fileURL)
                    // Update descriptor to point to this local file
                    // We modify the descriptor locally before passing it to cacheStore/pipeline
                    descriptor = DiverItemDescriptor(
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
                        sessionID: descriptor.sessionID,
                        coverImageURL: fileURL, // <--- Link payload here
                        placeID: descriptor.placeID,
                        latitude: descriptor.latitude,
                        longitude: descriptor.longitude,
                        purposes: descriptor.purposes,
                        processingLog: ["[\(Date().formatted())] Created from Payload persistence"]
                    )
                } catch {
                    print("⚠️ Failed to persist payload for item \(descriptor.id): \(error)")
                }
            }
            
            // 1. Link Enrichment
            if let linkService = linkEnrichmentService, let url = descriptor.urlValue {
                if let enriched = try? await linkService.enrich(url: url) {
                    descriptor = apply(enrichment: enriched, to: descriptor)
                }
            }
            
            // 2. Context Enrichment (e.g. DuckDuckGo for additional query context or location)
            // If we had location, we could use contextEnrichmentService.enrich(location: ...)
            // For now, if descriptor has a query/title without URL, we might use it.
            // Or if we want to augment the descriptor with more context.
            // Integration note: DDG is query based.
            
            try await cacheStore.store(descriptor: descriptor)
            
            // 3. Handle Attachments (Session Images)
            // Fix: Previously ignored, causing data loss for multi-image sessions
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
            purposes: descriptor.purposes, // Preserve existing purposes
            processingLog: descriptor.processingLog + ["[\(Date().formatted())] Enriched with Link Metadata"]
        )
    }
}
