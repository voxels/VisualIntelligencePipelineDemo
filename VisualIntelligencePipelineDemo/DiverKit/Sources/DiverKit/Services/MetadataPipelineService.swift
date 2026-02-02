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
                
                // Generate summaries for sessions and collections that had items processed
                if successCount > 0 {
                    await self.generatePendingSessionSummaries()
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
        
        // CRITICAL: Fetch the item from THIS service's context to avoid context mismatch
        // The passed item may be from a different context (e.g., view's context)
        let itemID = item.id
        let fetchDescriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        
        guard let localItem = try modelContext.fetch(fetchDescriptor).first else {
            print("❌ processItemImmediately: Could not find item \(itemID) in pipeline context")
            throw NSError(domain: "MetadataPipelineService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Item not found"])
        }
        
        localItem.statusRaw = ProcessingStatus.processing.rawValue
        localItem.updatedAt = Date() // CRITICAL: Update timestamp to prevent zombie check from marking as stalled
        localItem.processingLog.append("\(Date().formatted()): Starting high-priority 'Process Now' workflow.")
        try? modelContext.save()
        
        do {
            let localPipeline = LocalPipelineService(modelContext: modelContext)
            
            let targetURL = localItem.url
            let targetTitle = localItem.title
            
            // CRITICAL: Detect if item has a user-set location that should be preserved
            // If so, pass nil for locationService to prevent GPS override
            // Be STRICT here - only detect truly user-explicit overrides
            let hasUserSetLocation: Bool = {
                guard let placeContext = localItem.placeContext else { return false }
                
                // Contact-set location (explicitly chosen from contacts)
                if placeContext.contactIdentifier != nil { return true }
                
                // MapKit/manual location override (explicitly chosen from map)
                if let placeID = placeContext.placeID {
                    if placeID.hasPrefix("mapkit-") || placeID.hasPrefix("mk-") || placeID == "home-location" {
                        return true
                    }
                }
                
                // NOTE: Don't just check for name + coordinates, as that catches pipeline-enriched items too
                return false
            }()
            
            // Skip locationService if user has already set a location
            let effectiveLocationService = hasUserSetLocation ? nil : locationService
            
            if hasUserSetLocation {
                localItem.processingLog.append("\(Date().formatted()): Preserving user-set location: \(localItem.placeContext?.name ?? "Unknown")")
            }
            
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
            
            // CRITICAL: Clear all calculated data for fresh reprocessing
            // Preserve: id, url, rawPayload, sessionID, createdAt, source, photosAssetIdentifier
            localItem.summary = nil
            localItem.transcription = nil
            localItem.tags = []
            localItem.purposes = []
            localItem.categories = []
            localItem.questions = []
            if !hasUserSetLocation {
                localItem.placeContextData = nil
            }
            localItem.webContextData = nil
            localItem.documentContextData = nil
            localItem.qrContextData = nil
            localItem.activityContextData = nil
            // Note: Don't clear weatherContextData - it's capture-time only
            localItem.processingLog.append("\(Date().formatted()): Cleared calculated data for fresh reprocessing (preserving user overrides: \(hasUserSetLocation)).")
            
            // CRITICAL: Also clear parent session summary so it regenerates with new item data
            if let sessionID = localItem.sessionID {
                let sessionFetch = FetchDescriptor<DiverSession>(
                    predicate: #Predicate { $0.sessionID == sessionID }
                )
                if let session = try? modelContext.fetch(sessionFetch).first {
                    session.summary = nil
                    session.updatedAt = Date()
                    localItem.processingLog.append("\(Date().formatted()): Cleared parent session summary for regeneration.")
                }
            }
            
            try? modelContext.save()
            
            // Create descriptor with the item's actual ID to ensure correct item is updated
            let descriptor = DiverItemDescriptor(
                id: localItem.id,
                url: localItem.url ?? "",
                title: localItem.title ?? "",
                type: DiverItemType(rawValue: localItem.entityType ?? "web") ?? .web,
                attributionID: localItem.attributionID,
                masterCaptureID: localItem.masterCaptureID,
                sessionID: localItem.sessionID
            )
            
            if let input = input {
                _ = try await localPipeline.process(
                    input: input,
                    descriptor: descriptor,
                    enrichmentService: enrichmentService,
                    locationService: effectiveLocationService,
                    foursquareService: foursquareService,
                    duckDuckGoService: duckDuckGoService,
                    weatherService: weatherService,
                    indexingService: indexingService,
                    contextService: contextService
                )
            } else {
                 // Fallback: create a temporary input from item data
                 // Include rawPayload for image captures
                 var imageData: Data? = localItem.rawPayload
                 
                 // If no rawPayload but has photosAssetIdentifier, load on-demand
                 if imageData == nil, let assetId = localItem.photosAssetIdentifier {
                     imageData = await PhotosAssetLoader.shared.loadImageData(identifier: assetId)
                 }
                 
                 // Use original source so pipeline knows how to handle (e.g., photoLibraryImport runs OCR)
                 let fallbackInput = LocalInput(
                     createdAt: localItem.createdAt,
                     url: localItem.url,
                     text: localItem.title,
                     source: localItem.source ?? "reprocessing",
                     inputType: localItem.entityType ?? "web",
                     rawPayload: imageData
                 )
                 
                 modelContext.insert(fallbackInput)
                 _ = try await localPipeline.process(
                    input: fallbackInput,
                    descriptor: descriptor,
                    enrichmentService: enrichmentService,
                    locationService: effectiveLocationService,
                    foursquareService: foursquareService,
                    duckDuckGoService: duckDuckGoService,
                    weatherService: weatherService,
                    indexingService: indexingService,
                    contextService: contextService
                )
            }
            
            // Mark as ready if processing succeeded
            // CRITICAL: Set statusRaw directly (not through @Transient status) to ensure SwiftData persistence
            localItem.statusRaw = ProcessingStatus.ready.rawValue
            localItem.processingLog.append("\(Date().formatted()): Processing completed successfully.")
            try modelContext.save()
            
        } catch {
            // Handle errors - don't leave item stuck in processing state
            localItem.statusRaw = ProcessingStatus.failed.rawValue
            localItem.failureCount += 1
            localItem.processingLog.append("\(Date().formatted()): Processing failed - \(error.localizedDescription)")
            try? modelContext.save()
            print("❌ processItemImmediately failed: \(error)")
            throw error
        }
        
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
        
        // 3. Process queued ProcessedItems that have no LocalInput (orphaned items after crash/resume)
        await processQueuedOrphanItems()
        
        // 4. Process imported PHAsset items (Photo Library imports with no rawPayload)
        await processImportedPHAssetItems()
    }
    
    /// Process queued items that have no corresponding LocalInput (e.g., stalled items reset earlier)
    private func processQueuedOrphanItems() async {
        let queuedFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "queued" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        guard let queuedItems = try? modelContext.fetch(queuedFetch), !queuedItems.isEmpty else {
            return
        }
        
        DiverLogger.pipeline.info("Processing \(queuedItems.count) queued items without LocalInput")
        
        for item in queuedItems {
            if Task.isCancelled { break }
            
            // Check if there's already a LocalInput for this item
            let itemURL = item.url
            let urlFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.url == itemURL })
            if let _ = try? modelContext.fetch(urlFetch).first {
                // LocalInput exists, will be processed by step 2
                continue
            }
            
            // No LocalInput? Process this orphaned item directly
            do {
                try await processItemImmediately(item)
            } catch {
                DiverLogger.pipeline.error("Failed to process orphaned queued item \(item.id): \(error)")
                item.status = .failed
                item.failureCount += 1
                item.processingLog.append("\(Date().formatted()): Failed to resume - \(error.localizedDescription)")
                try? modelContext.save()
            }
        }
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
            
            // Load image data from PHAsset using shared loader
            // This handles both images and videos (extracting best frame)
            guard let imageData = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetIdentifier) else {
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
                    photosAssetIdentifier: item.photosAssetIdentifier,
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


    private func handle(record: DiverQueueRecord) async throws {
        let descriptor = record.item.descriptor

        DiverLogger.pipeline.debug("Creating LocalInput from descriptor - url: \(descriptor.url), type: \(descriptor.type.rawValue), attributionID: \(descriptor.attributionID ?? "nil")")

        // Determine payload: use record payload, or load from PHAsset if available
        var payload = record.item.payload
        
        if payload == nil, let assetIdentifier = record.item.photosAssetIdentifier {
            // Load data on-demand from PHAsset (memory-safe: 1024x1024 max)
            print("📸 [MetadataPipeline] Loading data from PHAsset: \(assetIdentifier)")
            // Use shared loader for consistent video frame extraction
            payload = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetIdentifier)
            
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
    
    // MARK: - Session Summary Generation
    
    /// Generate LLM summaries for sessions by aggregating item summaries
    public func generatePendingSessionSummaries() async {
        guard let contextService = self.contextService else {
            print("⚠️ [MetadataPipeline] No contextService available for session summaries")
            return
        }
        
        do {
            // Find sessions that need summaries regenerated
            // Either nil summary, or empty summary
            let sessionDescriptor = FetchDescriptor<DiverSession>(
                predicate: #Predicate { $0.summary == nil }
            )
            let sessions = try modelContext.fetch(sessionDescriptor)
            
            print("🔄 [MetadataPipeline] Found \(sessions.count) sessions needing summaries")
            
            for session in sessions {
                // Fetch all items for this session
                let sessionID = session.sessionID
                let itemDescriptor = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.sessionID == sessionID },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                
                guard let items = try? modelContext.fetch(itemDescriptor), !items.isEmpty else {
                    continue
                }
                
                // Build aggregated context from item source material (transcriptions, not summaries)
                let itemContexts = items.compactMap { item -> String? in
                    var parts: [String] = []
                    if let title = item.title, !title.isEmpty { parts.append("Title: \(title)") }
                    if let transcription = item.transcription, !transcription.isEmpty {
                        parts.append("OCR: \(transcription.prefix(300))")
                    }
                    if let place = item.placeContext?.name, !place.isEmpty {
                        parts.append("Place: \(place)")
                    }
                    return parts.isEmpty ? nil : parts.joined(separator: " | ")
                }.prefix(20) // Limit to avoid token overflow
                
                guard !itemContexts.isEmpty else { continue }
                
                let contextText = """
                Session with \(items.count) captures at \(session.locationName ?? "unknown location").
                
                Captured items:
                \(Array(itemContexts).joined(separator: "\n"))
                
                Generate a brief 1-2 sentence summary of what was captured in this session.
                """
                
                let llmSummary = try await contextService.summarizeText(contextText)
                
                session.summary = llmSummary
                session.updatedAt = Date()
                
                print("✅ [MetadataPipeline] Generated LLM summary for session '\(session.sessionID)': \(llmSummary.prefix(100))...")
            }
            
            try modelContext.save()
            
        } catch {
            print("⚠️ [MetadataPipeline] Failed to generate session summaries: \(error)")
        }
    }
    
    // MARK: - Collection Summary Generation
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
