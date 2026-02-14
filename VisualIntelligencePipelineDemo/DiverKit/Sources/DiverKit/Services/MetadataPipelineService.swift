import Foundation
import SwiftData
import DiverShared
import WidgetKit
import Photos
import AVFoundation
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// Thread-safe holder for UIBackgroundTaskIdentifier to safely share across isolation boundaries.
@MainActor
private final class BackgroundTaskHolder: Sendable {
    nonisolated(unsafe) var taskID: UIBackgroundTaskIdentifier = .invalid
}
#endif

@MainActor
@Observable
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
    
    // MARK: - Queue Progress (observed by QueueProgressView)
    public var isProcessingQueue: Bool = false
    private var resetTask: Task<Void, Never>?
    public var queueTotalCount: Int = 0
    public var queueCompletedCount: Int = 0
    public var queueCurrentItemTitle: String? = nil
    /// Granular phase description, e.g. "Loading image…", "Analyzing content…"
    public var queueStatusMessage: String? = nil
    public var queueProgress: Double {
        guard queueTotalCount > 0 else { return 0 }
        return Double(queueCompletedCount) / Double(queueTotalCount)
    }
    
    private var currentTask: Task<Void, Never>?
    private var queueGeneration: Int = 0

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
    
    /// Cancels all in-flight processing. Call when the app enters background or terminates.
    public func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
        resetTask?.cancel()
        resetTask = nil
        isProcessingQueue = false
        queueTotalCount = 0
        queueCompletedCount = 0
        queueCurrentItemTitle = nil
        queueStatusMessage = nil
        print("🛑 [MetadataPipeline] Processing cancelled (app backgrounded)")
    }

    public func processPendingQueue() async throws {
        // Cancel any existing task and any pending reset
        currentTask?.cancel()
        resetTask?.cancel()
        
        // Increment generation so cancelled tasks don't reset our progress
        queueGeneration += 1
        let myGeneration = queueGeneration
        
        // Register background task on main actor BEFORE entering detached context
        #if os(iOS)
        print("🔄 [MetadataPipeline] Starting processPendingQueue (detached, utility priority)")
        // Use a reference type to allow the expiration handler to end the task
        let bgTaskHolder = BackgroundTaskHolder()
        bgTaskHolder.taskID = UIApplication.shared.beginBackgroundTask(withName: "DiverMetadataPipeline") {
            UIApplication.shared.endBackgroundTask(bgTaskHolder.taskID)
            bgTaskHolder.taskID = .invalid
        }
        #endif
        
        let task = Task.detached(priority: .utility) { [self] in
            #if os(iOS)
            defer {
                let finalID = bgTaskHolder.taskID
                if finalID != .invalid {
                    Task { @MainActor in
                        UIApplication.shared.endBackgroundTask(finalID)
                    }
                }
            }
            #endif

            // Show progress immediately — individual phases will add to the counts
            await MainActor.run {
                self.isProcessingQueue = true
                self.queueTotalCount = 0
                self.queueCompletedCount = 0
                self.queueCurrentItemTitle = nil
                self.queueStatusMessage = "Checking queue…"
            }
            // Yield so SwiftUI can render the overlay before heavy work begins
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms to ensure UI renders

            do {
                // 1. Resume any stuck items from previous sessions (DB persistence)
                // Hops to @MainActor for SwiftData operations
                DiverLogger.queue.debug("Checking for stuck items or pending database transactions...")
                try await self.resumeSuspendedQueue()
                if Task.isCancelled { 
                    DiverLogger.queue.debug("Queue processing cancelled after resumeSuspendedQueue")
                    // Only reset progress if no newer task has taken over
                    await MainActor.run {
                        if self.queueGeneration == myGeneration {
                            self.resetQueueProgress()
                        }
                    }
                    return 
                }

                // 2. Process disk queue records (shared links from DiverQueueStore)
                let records = try await MainActor.run { try self.queueStore.pendingEntries() }
                if !records.isEmpty {
                    print("🔄 [MetadataPipeline] Processing \(records.count) entries from disk...")
                    DiverLogger.queue.info("Processing \(records.count) pending queue entries from disk")
                    
                    await MainActor.run {
                        self.queueTotalCount += records.count
                    }

                    var successCount = 0
                    var errorCount = 0

                    for record in records {
                        if Task.isCancelled { break }
                        
                        let itemTitle = record.item.descriptor.title
                        await MainActor.run {
                            self.queueCurrentItemTitle = itemTitle
                            self.queueStatusMessage = "Processing shared link…"
                        }
                        
                        do {
                            print("📦 [MetadataPipeline] Starting: \(record.item.id)")
                            try await self.handle(record: record)
                            try await self.saveWithRetry()
                            try await MainActor.run { try self.queueStore.remove(record) }
                            successCount += 1
                            await MainActor.run { self.queueCompletedCount += 1 }
                            print("✅ [MetadataPipeline] Finished: \(record.item.id)")
                            DiverLogger.queue.debug("Successfully processed and persisted queue item: \(record.item.id)")
                        } catch {
                            errorCount += 1
                            print("❌ [MetadataPipeline] Failed \(record.fileURL.lastPathComponent): \(error)")
                            DiverLogger.queue.logError(error, context: "Error processing record \(record.fileURL.lastPathComponent)")
                            try? await self.handleFailure(record: record, error: error)
                            try? await self.saveWithRetry()
                            try? await MainActor.run { try self.queueStore.remove(record) }
                            await MainActor.run { self.queueCompletedCount += 1 }
                            continue
                        }
                    }
                    
                    print("🏁 [MetadataPipeline] Disk queue complete. Success: \(successCount), Failed: \(errorCount)")
                    DiverLogger.queue.info("Queue processing complete - success: \(successCount), failed: \(errorCount), total: \(records.count)")
                    
                    if successCount > 0 {
                        await self.generatePendingSessionSummaries()
                        await self.generatePendingCollectionSummaries()
                    }
                } else {
                    print("📂 [MetadataPipeline] No pending files in DiverQueueStore.")
                    DiverLogger.queue.debug("No pending files found in DiverQueueStore.")
                }
                
                // Reset progress after all phases complete
                await MainActor.run {
                    if self.queueGeneration == myGeneration {
                        self.resetQueueProgress()
                    }
                }
                
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                DiverLogger.queue.error("Queue processing failed: \(error)")
                await MainActor.run {
                    if self.queueGeneration == myGeneration {
                        self.resetQueueProgress()
                    }
                }
            }
        }
        
        self.currentTask = task
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
            
            // Add to running total
            queueTotalCount += pendingInputs.count
            queueStatusMessage = "Resuming interrupted items…"
            
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
                        queueTotalCount -= 1 // Already done, don't count
                        continue
                    }
                    
                    queueCurrentItemTitle = input.text ?? input.url ?? "Pending item"
                    queueStatusMessage = "Processing pending item…"
                    
                    // Recover descriptor from LocalInput's cached JSON (if available)
                    // This ensures sessionID and purposes survive cancellation/crash recovery
                    var recoveredDescriptor: DiverItemDescriptor? = nil
                    if let json = input.descriptorJSON {
                        recoveredDescriptor = try? JSONDecoder().decode(DiverItemDescriptor.self, from: json)
                    }
                    
                    // Re-run process. logic checks for existing items automatically.
                    _ = try await localPipeline.process(
                        input: input,
                        descriptor: recoveredDescriptor,
                        enrichmentService: self.enrichmentService,
                        locationService: self.locationService,
                        foursquareService: self.foursquareService,
                        duckDuckGoService: self.duckDuckGoService,
                        weatherService: self.weatherService,
                        indexingService: self.indexingService,
                        contextService: self.contextService
                    )
                    queueCompletedCount += 1
                } catch {
                    DiverLogger.pipeline.error("Failed to resume input \(input.id): \(error)")
                    queueCompletedCount += 1
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
    /// Excludes photoLibraryImport items which are handled by processImportedPHAssetItems.
    private func processQueuedOrphanItems() async {
        let queuedFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "queued" && $0.source != "photoLibraryImport" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        guard let queuedItems = try? modelContext.fetch(queuedFetch), !queuedItems.isEmpty else {
            return
        }
        
        DiverLogger.pipeline.info("Processing \(queuedItems.count) queued items without LocalInput")
        
        // Add to running total (parent already set isProcessingQueue = true)
        queueTotalCount += queuedItems.count
        
        for item in queuedItems {
            if Task.isCancelled { break }
            
            // Check if there's already a LocalInput for this item
            let itemURL = item.url
            let urlFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.url == itemURL })
            if let _ = try? modelContext.fetch(urlFetch).first {
                // LocalInput exists, will be processed by step 2
                queueTotalCount -= 1 // Don't count items handled elsewhere
                continue
            }
            
            queueCurrentItemTitle = item.title ?? item.filename ?? "Processing item"
            queueStatusMessage = "Processing queued item…"
            
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
            
            queueCompletedCount += 1
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
        
        print("📸 [MetadataPipeline] Processing \(queuedItems.count) imported PHAsset items (concurrent prefetch)...")
        DiverLogger.pipeline.info("Processing \(queuedItems.count) imported PHAsset items")
        
        var successCount = 0
        var errorCount = 0
        
        // Add to running total (parent already set isProcessingQueue = true)
        queueTotalCount += queuedItems.count
        
        // Prefetch pattern: load next item's data while current item processes.
        // This overlaps PHAsset I/O with Vision + LLM computation.
        var prefetchTask: Task<Data?, Never>? = nil
        
        for (index, item) in queuedItems.enumerated() {
            if Task.isCancelled { break }
            
            guard let assetIdentifier = item.photosAssetIdentifier else {
                item.status = .failed
                item.processingLog.append("\(Date().formatted()): No photosAssetIdentifier found")
                errorCount += 1
                queueCompletedCount += 1
                continue
            }
            
            // Start prefetching the NEXT item's data while we process this one
            let nextItem = (index + 1 < queuedItems.count) ? queuedItems[index + 1] : nil
            let nextPrefetch: Task<Data?, Never>?
            if let nextAssetID = nextItem?.photosAssetIdentifier {
                nextPrefetch = Task.detached(priority: .utility) {
                    await PhotosAssetLoader.shared.loadBestFrame(identifier: nextAssetID)
                }
            } else {
                nextPrefetch = nil
            }
            
            queueCurrentItemTitle = item.title ?? item.filename ?? "Photo Import"
            queueStatusMessage = "Loading image data…"
            
            // Use prefetched data if available (from previous iteration), otherwise load now
            let imageData: Data?
            if let prefetched = prefetchTask {
                imageData = await prefetched.value
            } else {
                imageData = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetIdentifier)
            }
            prefetchTask = nextPrefetch
            
            guard let imageData else {
                item.status = .failed
                item.processingLog.append("\(Date().formatted()): Failed to load data from PHAsset")
                errorCount += 1
                queueCompletedCount += 1
                continue
            }
            
            do {
                item.status = .processing
                item.processingLog.append("\(Date().formatted()): Processing PHAsset import")
                queueStatusMessage = "Analyzing content…"
                try? modelContext.save()
                
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
                
                queueStatusMessage = "Running pipeline…"
                _ = try await localPipeline.process(
                    input: localInput,
                    descriptor: descriptor,
                    enrichmentService: self.enrichmentService,
                    locationService: nil,
                    foursquareService: self.foursquareService,
                    duckDuckGoService: self.duckDuckGoService,
                    weatherService: self.weatherService,
                    indexingService: self.indexingService,
                    contextService: self.contextService
                )
                
                try? modelContext.save()
                successCount += 1
                queueCompletedCount += 1
                print("✅ [MetadataPipeline] Processed PHAsset: \(item.id)")
                
            } catch {
                item.status = .failed
                item.processingLog.append("\(Date().formatted()): Processing failed - \(error.localizedDescription)")
                errorCount += 1
                queueCompletedCount += 1
                print("❌ [MetadataPipeline] Failed PHAsset: \(item.id) - \(error)")
            }
        }
        
        try? modelContext.save()
        print("📸 [MetadataPipeline] PHAsset processing complete. Success: \(successCount), Failed: \(errorCount)")
    }
    
    /// Clears queue progress state after a brief delay so the "complete" state is visible.
    /// MUST be called from MainActor or wrapped in MainActor.run.
    @MainActor
    private func resetQueueProgress() {
        queueCurrentItemTitle = nil
        queueStatusMessage = "Complete"
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard !Task.isCancelled else { return }
            self?.isProcessingQueue = false
            self?.queueTotalCount = 0
            self?.queueCompletedCount = 0
            self?.queueStatusMessage = nil
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
            rawPayload: payload,
            sessionID: descriptor.sessionID,
            purposes: Array(descriptor.purposes)
        )
        // Persist full descriptor for crash recovery — if the task is cancelled
        // before process() completes, resumeSuspendedQueue can recover it.
        localInput.descriptorJSON = try? JSONEncoder().encode(descriptor)

        modelContext.insert(localInput)
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        
        // For photo library imports, pass nil for locationService to prevent GPS override
        // The descriptor already contains the photo's original location
        let useLocationService = record.item.source != "photoLibraryImport" ? locationService : nil
        
        let processedItem = try await localPipeline.process(
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
        
        // Assign depth payload from queue item (captured atomically with photo)
        // No extra save() here — the context is saved by the caller to avoid WAL contention
        if let depthData = record.item.depthPayload {
            processedItem.depthPayload = depthData
            print("📐 Depth map assigned to ProcessedItem: \(depthData.count) bytes")
        }

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
                sessionID: descriptor.sessionID, // Ensure we pass the session ID if known from descriptor
                processingLog: ["\(Date().formatted()): Initial processing failure: \(error.localizedDescription)"], 
                failureCount: 1
            )
            modelContext.insert(failedItem)
            
            // CRITICAL: Ensure even failed items have a session so they aren't orphaned in UI
            let localPipeline = LocalPipelineService(modelContext: modelContext)
            localPipeline.syncSession(for: failedItem)
            
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
                
                let llmSummary: String
                
                if ContextQuestionService.isAvailable {
                    llmSummary = try await contextService.summarizeText(contextText)
                } else {
                    // Heuristic Fallback
                    let count = items.count
                    // Use itemContexts (which has titles/OCR) to extract unique titles
                    let titles = items.compactMap { $0.title }
                        .filter { !$0.isEmpty && $0 != "Untitled" && $0 != "Visual Capture" }
                        .prefix(3)
                        .joined(separator: ", ")
                    
                    llmSummary = "Session with \(count) items. Includes: \(titles.isEmpty ? "Captured content" : titles)."
                }
                
                session.summary = llmSummary
                session.updatedAt = Date()
                
                print("✅ [MetadataPipeline] Generated summary for session '\(session.sessionID)': \(llmSummary.prefix(100))...")
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
                
                let summary: String
                
                if ContextQuestionService.isAvailable {
                    summary = try await contextService.summarizeText(contextText)
                } else {
                    // Heuristic Fallback
                    let count = allItems.count
                    let examples = allItems.compactMap { $0.title }.filter { !$0.isEmpty && $0 != "Untitled" }.prefix(3).joined(separator: ", ")
                    summary = "Collection containing \(count) items. Includes: \(examples.isEmpty ? "Various items" : examples)."
                }
                
                collection.llmSummary = summary
                collection.updatedAt = Date()
                
                print("✅ [MetadataPipeline] Generated summary for collection '\(collection.name)'")
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
