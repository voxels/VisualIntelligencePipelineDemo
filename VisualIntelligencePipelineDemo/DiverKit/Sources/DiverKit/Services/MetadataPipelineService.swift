import Foundation
import SwiftData
import DiverShared
import WidgetKit
import Photos
import AVFoundation
#if os(iOS)
import UIKit
#endif


@MainActor
public final class MetadataPipelineService {
    private let queueStore: DiverQueueStore
    private let modelContext: ModelContext

    public var enrichmentService: LinkEnrichmentService?
    public var locationService: LocationProvider?
    public var foursquareService: ContextualEnrichmentService?
    public var duckDuckGoService: ContextualEnrichmentService?
    public var weatherService: WeatherEnrichmentService?
    public var indexingService: KnowledgeGraphIndexingService?
    public var contextService: ContextQuestionService?
    
    private var currentTask: Task<Void, Never>?

    public init(
        queueStore: DiverQueueStore,
        modelContext: ModelContext,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        foursquareService: ContextualEnrichmentService? = nil,
        duckDuckGoService: ContextualEnrichmentService? = nil,
        weatherService: WeatherEnrichmentService? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil,
        contextService: ContextQuestionService? = nil
    ) {
        self.queueStore = queueStore
        self.modelContext = modelContext
        self.enrichmentService = enrichmentService
        self.locationService = locationService
        self.foursquareService = foursquareService
        self.duckDuckGoService = duckDuckGoService
        self.weatherService = weatherService
        self.indexingService = indexingService
        self.contextService = contextService
    }

    public func processPendingQueue() async throws {
        // Cancel any existing task
        currentTask?.cancel()
        
        let task = Task(priority: .userInitiated) {
            #if os(iOS)
            var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
            print("🔄 [MetadataPipeline] Starting processPendingQueue (userInitiated priority)")
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "DiverMetadataPipeline") {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
            #endif

            do {
                // 1. Resume any stuck items from previous sessions (DB persistence)
                DiverLogger.queue.debug("Checking for stuck items or pending database transactions...")
                try await resumeSuspendedQueue()
                if Task.isCancelled { 
                    DiverLogger.queue.debug("Queue processing cancelled after resumeSuspendedQueue")
                    return 
                }

                let records = try queueStore.pendingEntries()
                if records.isEmpty {
                    print("📂 [MetadataPipeline] No pending files in DiverQueueStore.")
                    DiverLogger.queue.debug("No pending files found in DiverQueueStore.")
                    return
                } else {
                    print("🔄 [MetadataPipeline] Processing \(records.count) entries from disk...")
                    DiverLogger.queue.info("Processing \(records.count) pending queue entries from disk")
                }

                var successCount = 0
                var errorCount = 0

                for record in records {
                    if Task.isCancelled { break }
                    do {
                        print("📦 [MetadataPipeline] Starting: \(record.item.id)")
                        try await self.handle(record: record)
                        
                        // CRITICAL: Save to DB BEFORE removing from disk queue to prevent data loss on crash/error
                        try await self.saveWithRetry()
                        
                        try queueStore.remove(record)
                        successCount += 1
                        print("✅ [MetadataPipeline] Finished: \(record.item.id)")
                        DiverLogger.queue.debug("Successfully processed and persisted queue item: \(record.item.id)")
                    } catch {
                        errorCount += 1
                        print("❌ [MetadataPipeline] Failed \(record.fileURL.lastPathComponent): \(error)")
                        DiverLogger.queue.logError(error, context: "Error processing record \(record.fileURL.lastPathComponent)")
                        
                        try? await handleFailure(record: record, error: error)
                        // Even on failure, if handleFailure succeeded in updating DB, we should save and remove
                        try? await self.saveWithRetry()
                        try? queueStore.remove(record)
                        continue
                    }
                }
                
                print("🏁 [MetadataPipeline] Complete. Success: \(successCount), Failed: \(errorCount)")
                DiverLogger.queue.info("Queue processing complete - success: \(successCount), failed: \(errorCount), total: \(records.count)")
                
                // Generate summaries for collections that had items processed
                if successCount > 0 {
                    await self.generatePendingCollectionSummaries()
                }
                
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                DiverLogger.queue.error("Queue processing failed: \(error)")
            }
        }
        
        self.currentTask = task
        _ = await task.result
    }

    /// Helper to save with retry logic for 'database is busy' errors
    private func saveWithRetry(attempts: Int = 3) async throws {
        var lastError: Error?
        for i in 0..<attempts {
            do {
                try modelContext.save()
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                // Check for SQLite busy or lock errors (Cocoa codes 256, 134080)
                if nsError.code == 256 || nsError.code == 134080 || nsError.localizedDescription.contains("busy") {
                    DiverLogger.storage.warning("Database busy, retrying save (\(i+1)/\(attempts))...")
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000 * (i + 1))) // Exponential backoff
                    continue
                }
                throw error
            }
        }
        if let lastError { throw lastError }
    }

    public func processItemImmediately(_ item: ProcessedItem) async throws {
        // Cancel current queue work to avoid conflict/slowness
        currentTask?.cancel()
        
        item.status = .processing
        item.processingLog.append("\(Date().formatted()): Starting high-priority 'Process Now' workflow.")
        try? modelContext.save()
        
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        
        let targetURL = item.url
        let targetTitle = item.title
        
        // Find or create LocalInput
        // Splitting into two fetches to resolve: 'PredicateExpressions.Disjunction' compiler error
        var input: LocalInput?
        
        if let url = targetURL {
            let urlFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.url == url })
            input = try? modelContext.fetch(urlFetch).first
        }
        
        if input == nil, let title = targetTitle {
            let titleFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.text == title })
            input = try? modelContext.fetch(titleFetch).first
        }
        
        if let input = input {
            _ = try await localPipeline.process(
                input: input,
                enrichmentService: enrichmentService,
                locationService: locationService,
                foursquareService: foursquareService,
                duckDuckGoService: duckDuckGoService,
                weatherService: weatherService,
                indexingService: indexingService,
                contextService: contextService
            )
        } else {
             // Fallback: create a temporary input from item data
             let fallbackInput = LocalInput(url: item.url, source: "forced", inputType: item.entityType ?? "web")
             modelContext.insert(fallbackInput)
             _ = try await localPipeline.process(
                input: fallbackInput,
                enrichmentService: enrichmentService,
                locationService: locationService,
                foursquareService: foursquareService,
                duckDuckGoService: duckDuckGoService,
                weatherService: weatherService,
                indexingService: indexingService,
                contextService: contextService
            )
        }
        
        try modelContext.save()
        
        // Restart the rest of the queue in background
        Task {
            try? await self.processPendingQueue()
        }
    }

    /// Resumes processing for items that may have been interrupted (app termination, crash)
    private func resumeSuspendedQueue() async throws {
        // 1. Reset "Processing" -> "Queued" (Zombie Check)
        // Only reset if they have been stuck for more than 5 minutes to avoid flapping
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let processingFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "processing" && $0.updatedAt < fiveMinutesAgo }
        )
        let stuckItems = try modelContext.fetch(processingFetch)
        
        if !stuckItems.isEmpty {
            DiverLogger.pipeline.warning("Found \(stuckItems.count) stuck items in processing state for >5 mins. Resetting to queued.")
            for item in stuckItems {
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): Resumed from stalled state (timeout)")
            }
            try modelContext.save()
        }
        
        // 2. Process all persistent LocalInputs (Pending Work)
        // LocalInput is only deleted upon successful completion of LocalPipelineService.process
        let inputFetch = FetchDescriptor<LocalInput>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let pendingInputs = try modelContext.fetch(inputFetch)
        
        if !pendingInputs.isEmpty {
            DiverLogger.pipeline.info("Resuming \(pendingInputs.count) pending transactions from database")
            
            let localPipeline = LocalPipelineService(modelContext: modelContext)
            
            for input in pendingInputs {
                do {
                    // CRITICAL FIX: Skip LocalInputs that already have a fully processed item
                    // This prevents reprocessing items that completed successfully but whose
                    // LocalInput deletion was interrupted (crash, timing issue)
                    let inputId = input.id.uuidString
                    let checkFetch = FetchDescriptor<ProcessedItem>(
                        predicate: #Predicate { $0.inputId == inputId && $0.statusRaw == "ready" }
                    )
                    if let existingReady = try? modelContext.fetch(checkFetch).first {
                        DiverLogger.pipeline.debug("Skipping already-completed input \(inputId) - ProcessedItem \(existingReady.id) is ready")
                        // Clean up the orphaned LocalInput
                        modelContext.delete(input)
                        continue
                    }
                    
                    // Re-run process. logic checks for existing items automatically.
                    _ = try await localPipeline.process(
                        input: input,
                        enrichmentService: self.enrichmentService,
                        locationService: self.locationService,
                        foursquareService: self.foursquareService,
                        duckDuckGoService: self.duckDuckGoService,
                        weatherService: self.weatherService,
                        indexingService: self.indexingService,
                        contextService: self.contextService
                    )
                } catch {
                    DiverLogger.pipeline.error("Failed to resume input \(input.id): \(error)")
                    // If it fails repeatedly, it stays in the database as a pending input
                }
            }
            try modelContext.save()
        }
        
        // 3. Process imported PHAsset items (Photo Library imports with no rawPayload)
        await processImportedPHAssetItems()
    }
    
    /// Process imported items that have a photosAssetIdentifier but no rawPayload.
    /// Loads data ONE ITEM AT A TIME to prevent memory pressure.
    private func processImportedPHAssetItems() async {
        // Fetch queued items that came from photo library import
        let queuedFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { 
                $0.statusRaw == "queued" && 
                $0.source == "photoLibraryImport" 
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        guard let queuedItems = try? modelContext.fetch(queuedFetch), !queuedItems.isEmpty else {
            return
        }
        
        print("📸 [MetadataPipeline] Processing \(queuedItems.count) imported PHAsset items...")
        DiverLogger.pipeline.info("Processing \(queuedItems.count) imported PHAsset items")
        
        var successCount = 0
        var errorCount = 0
        
        // Process ONE item at a time for memory safety
        for item in queuedItems {
            if Task.isCancelled { break }
            
            guard let assetIdentifier = item.photosAssetIdentifier else {
                // No asset identifier - mark as failed
                item.status = .failed
                item.processingLog.append("\(Date().formatted()): No photosAssetIdentifier found")
                errorCount += 1
                continue
            }
            
            // Load image data from PHAsset
            guard let imageData = await loadDataFromPHAsset(identifier: assetIdentifier, isVideo: item.mediaType == "video") else {
                item.status = .failed
                item.processingLog.append("\(Date().formatted()): Failed to load data from PHAsset")
                errorCount += 1
                continue
            }
            
            do {
                item.status = .processing
                item.processingLog.append("\(Date().formatted()): Processing PHAsset import")
                try? modelContext.save()
                
                // Create LocalInput from the loaded data - use item's original date
                let localInput = LocalInput(
                    createdAt: item.createdAt,
                    url: nil,
                    source: "photoLibraryImport",
                    inputType: item.mediaType ?? "image",
                    rawPayload: imageData
                )
                
                modelContext.insert(localInput)
                
                let localPipeline = LocalPipelineService(modelContext: modelContext)
                let descriptor = DiverItemDescriptor(
                    id: item.id,
                    url: "",
                    title: item.title ?? item.filename ?? "Photo Import",
                    descriptionText: nil,
                    styleTags: [],
                    categories: ["photo_import"],
                    location: item.location,
                    price: nil,
                    type: item.mediaType == "video" ? .video : .image,
                    attributionID: nil,
                    masterCaptureID: nil,
                    sessionID: item.sessionID,
                    purposes: []
                )
                
                // Pass nil for locationService to prevent GPS override - use photo's original location
                _ = try await localPipeline.process(
                    input: localInput,
                    descriptor: descriptor,
                    enrichmentService: self.enrichmentService,
                    locationService: nil, // Don't override with current GPS
                    foursquareService: self.foursquareService,
                    duckDuckGoService: self.duckDuckGoService,
                    weatherService: self.weatherService,
                    indexingService: self.indexingService,
                    contextService: self.contextService
                )
                
                try? modelContext.save()
                successCount += 1
                print("✅ [MetadataPipeline] Processed PHAsset: \(item.id)")
                
            } catch {
                item.status = .failed
                item.processingLog.append("\(Date().formatted()): Processing failed - \(error.localizedDescription)")
                errorCount += 1
                print("❌ [MetadataPipeline] Failed PHAsset: \(item.id) - \(error)")
            }
            
            // Memory cleanup: pause briefly to allow ARC to reclaim
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second
        }
        
        try? modelContext.save()
        print("📸 [MetadataPipeline] PHAsset processing complete. Success: \(successCount), Failed: \(errorCount)")
    }
    
    /// Load image/video data from PHAsset
    /// For images: returns scaled image data
    /// For videos: extracts best frame using AestheticsScoringService
    private func loadDataFromPHAsset(identifier: String, isVideo: Bool) async -> Data? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            print("⚠️ PHAsset not found for identifier: \(identifier)")
            return nil
        }
        
        if isVideo {
            // For videos: request AVAsset and extract best frame
            return await loadBestFrameFromVideo(asset: asset)
        } else {
            // For images: request scaled image
            return await loadImageData(from: asset)
        }
    }
    
    // MARK: - PHImageManager Helpers (nonisolated to avoid actor isolation issues)
    // PHImageManager callbacks run on background dispatch queues.
    // By marking these as `nonisolated`, the continuation is not tied to MainActor,
    // so the callback can safely resume from any queue without actor isolation crashes.
    
    /// Request scaled image from PHAsset - nonisolated to avoid actor isolation with PHImageManager callback
    nonisolated private func requestImageFromPhotos(_ asset: PHAsset, targetSize: CGSize) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = image.jpegData(compressionQuality: 0.8)
                continuation.resume(returning: data)
            }
        }
    }
    
    /// Request AVAsset from PHAsset - nonisolated to avoid actor isolation with PHImageManager callback
    nonisolated private func requestAVAssetFromPhotos(_ asset: PHAsset) async -> AVURLAsset? {
        let videoOptions = PHVideoRequestOptions()
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.deliveryMode = .mediumQualityFormat
        
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
                continuation.resume(returning: avAsset as? AVURLAsset)
            }
        }
    }
    
    /// Load scaled image data from PHAsset
    private func loadImageData(from asset: PHAsset) async -> Data? {
        let targetSize = CGSize(width: 1024, height: 1024)
        return await requestImageFromPhotos(asset, targetSize: targetSize)
    }
    
    /// Load best frame from video using AestheticsScoringService
    private func loadBestFrameFromVideo(asset: PHAsset) async -> Data? {
        // Step 1: Get the AVAsset using nonisolated helper
        guard let avAsset = await requestAVAssetFromPhotos(asset) else {
            print("⚠️ [MetadataPipeline] AVURLAsset not available, using poster frame")
            return await loadImageData(from: asset)
        }
        
        // Step 2: Extract best frame using AestheticsScoringService
        do {
            let aestheticsService = AestheticsScoringService()
            let bestFrames = try await aestheticsService.extractBestFrames(from: avAsset.url, count: 1)
            
            if let bestFrame = bestFrames.first?.image {
                #if canImport(UIKit)
                let uiImage = UIImage(cgImage: bestFrame)
                let data = uiImage.jpegData(compressionQuality: 0.8)
                print("✅ [MetadataPipeline] Extracted best frame from video with score: \(bestFrames.first?.score ?? 0)")
                return data
                #else
                return nil
                #endif
            } else {
                print("⚠️ [MetadataPipeline] No frames extracted from video, using poster")
                return await loadImageData(from: asset)
            }
        } catch {
            print("❌ [MetadataPipeline] Failed to extract video frame: \(error)")
            return await loadImageData(from: asset)
        }
    }

    private func handle(record: DiverQueueRecord) async throws {
        let descriptor = record.item.descriptor

        DiverLogger.pipeline.debug("Creating LocalInput from descriptor - url: \(descriptor.url), type: \(descriptor.type.rawValue), attributionID: \(descriptor.attributionID ?? "nil")")

        // Determine payload: use record payload, or load from PHAsset if available
        var payload = record.item.payload
        
        if payload == nil, let assetIdentifier = record.item.photosAssetIdentifier {
            // Load data on-demand from PHAsset (memory-safe: 1024x1024 max)
            print("📸 [MetadataPipeline] Loading data from PHAsset: \(assetIdentifier)")
            payload = await loadDataFromPHAsset(identifier: assetIdentifier, isVideo: descriptor.type == .video)
            
            if payload == nil {
                print("⚠️ [MetadataPipeline] Failed to load PHAsset data for: \(assetIdentifier)")
            }
        }
        
        // Use the original creation date from the queue item, not current time
        let localInput = LocalInput(
            createdAt: record.item.createdAt,
            url: descriptor.url,
            source: record.item.source,
            inputType: descriptor.type.rawValue,
            rawPayload: payload
        )

        modelContext.insert(localInput)
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        
        // For photo library imports, pass nil for locationService to prevent GPS override
        // The descriptor already contains the photo's original location
        let useLocationService = record.item.source != "photoLibraryImport" ? locationService : nil
        
        _ = try await localPipeline.process(
            input: localInput,
            descriptor: descriptor,
            enrichmentService: enrichmentService,
            locationService: useLocationService,
            foursquareService: foursquareService,
            duckDuckGoService: duckDuckGoService,
            weatherService: weatherService,
            indexingService: indexingService,
            contextService: contextService
        )

        DiverLogger.storage.debug("Saved LocalInput to SwiftData - inputId: \(localInput.id.uuidString)")
    }

    public func refreshProcessedItems() async throws {
        DiverLogger.pipeline.info("Refreshing processed items")
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        try await localPipeline.refreshProcessedItems(
            enrichmentService: enrichmentService,
            locationService: locationService,
            foursquareService: foursquareService,
            duckDuckGoService: duckDuckGoService,
            weatherService: weatherService,
            indexingService: indexingService
        )
        WidgetCenter.shared.reloadAllTimelines()
        DiverLogger.pipeline.info("Processed items refresh complete")
    }

    private func handleFailure(record: DiverQueueRecord, error: Error) async throws {
        let descriptor = record.item.descriptor
        let id = descriptor.id 
        
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == id }
        )
        
        if let existing = try? modelContext.fetch(fetch).first {
            existing.failureCount += 1
            existing.processingLog.append("\(Date().formatted()): Failure (\(existing.failureCount)): \(error.localizedDescription)")
            
            if existing.failureCount > 2 {
                DiverLogger.pipeline.warning("Item \(id) failed too many times. Deleting.")
                modelContext.delete(existing)
            } else {
                existing.status = .failed
            }
            DiverLogger.pipeline.error("Updated failure status for item \(id): \(error)")
        } else {
            // Create a failed placeholder if it doesn't exist (so user can see it and retry)
            let failedItem = ProcessedItem(
                id: id,
                url: descriptor.url,
                title: descriptor.title,
                summary: "Failed to process: \(error.localizedDescription)",
                entityType: descriptor.type.rawValue,
                status: .failed,
                source: record.item.source,
                attributionID: descriptor.attributionID,
                processingLog: ["\(Date().formatted()): Initial processing failure: \(error.localizedDescription)"], failureCount: 1
            )
            modelContext.insert(failedItem)
            DiverLogger.pipeline.error("Created failed item \(id) due to: \(error)")
        }
        try modelContext.save()
    }
    public func runDataDiagnostics() async {
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        await localPipeline.runDataDiagnostics()
    }
    
    // MARK: - Collection Summary Generation
    
    /// Generate LLM summaries for collections that have newly processed items
    private func generatePendingCollectionSummaries() async {
        guard let contextService = self.contextService else {
            print("⚠️ [MetadataPipeline] No contextService available for collection summaries")
            return
        }
        
        do {
            // Find collections that need summaries (no llmSummary yet)
            let collectionDescriptor = FetchDescriptor<DiverCollection>(
                predicate: #Predicate { $0.llmSummary == nil }
            )
            let collections = try modelContext.fetch(collectionDescriptor)
            
            for collection in collections {
                // Fetch items for this collection's sessions
                var allItems: [ProcessedItem] = []
                
                for sessionID in collection.sessionIDs {
                    let itemDescriptor = FetchDescriptor<ProcessedItem>(
                        predicate: #Predicate { $0.sessionID == sessionID }
                    )
                    if let items = try? modelContext.fetch(itemDescriptor) {
                        allItems.append(contentsOf: items)
                    }
                }
                
                // Only generate summary if we have processed items
                guard !allItems.isEmpty else { continue }
                
                // Build summary context from items
                let itemSummaries = allItems.compactMap { item -> String? in
                    var parts: [String] = []
                    if let title = item.title { parts.append(title) }
                    if let summary = item.summary { parts.append(summary) }
                    return parts.isEmpty ? nil : parts.joined(separator: ": ")
                }.prefix(50)
                
                let contextText = "Collection: \(collection.name)\n\nItems:\n" + Array(itemSummaries).joined(separator: "\n")
                
                let llmSummary = try await contextService.summarizeText(contextText)
                
                collection.llmSummary = llmSummary
                collection.updatedAt = Date()
                
                print("✅ [MetadataPipeline] Generated LLM summary for collection '\(collection.name)'")
            }
            
            try modelContext.save()
            
        } catch {
            print("⚠️ [MetadataPipeline] Failed to generate collection summaries: \(error)")
        }
    }
}

// MARK: - SwiftUI Environment Support
import SwiftUI

public struct MetadataPipelineServiceKey: EnvironmentKey {
    nonisolated(unsafe) public static var defaultValue: MetadataPipelineService? = nil
}

public extension EnvironmentValues {
    @MainActor var metadataPipelineService: MetadataPipelineService? {
        get { self[MetadataPipelineServiceKey.self] }
        set { self[MetadataPipelineServiceKey.self] = newValue }
    }
}
