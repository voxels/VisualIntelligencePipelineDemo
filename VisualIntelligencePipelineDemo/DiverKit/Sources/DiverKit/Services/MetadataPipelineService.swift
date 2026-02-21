import Foundation
import os
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

@Observable
// MARK: - Thread Safety
// @unchecked Sendable is used because mutable state (`bgContext`, progress
// counters, `currentTask`) is guarded by:
//   1. `stateLock` (OSAllocatedUnfairLock) for synchronous property access
//   2. `queueGeneration` monotonic counter ensuring only one batch runs at a time
// The `[self]` strong capture in the detached task is intentional — the service
// must outlive its processing tasks.
public final class MetadataPipelineService: @unchecked Sendable {
    /// Protects mutable pipeline state from concurrent access.
    private let stateLock = OSAllocatedUnfairLock(initialState: 0)
    private let queueStore: DiverQueueStore
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext  // Main context — UI-driven operations only
    /// Background context created per-batch inside processPendingQueue.
    /// All background processing methods use this via `activeContext`.
    private var bgContext: ModelContext?
    /// Returns the background context if we're inside a batch, otherwise the main context.
    private var activeContext: ModelContext {
        bgContext ?? modelContext
    }

    public var enrichmentService: LinkEnrichmentService?
    public var locationService: LocationProvider?

    public var indexingService: KnowledgeGraphIndexingService?
    public var contextService: (any ContextProcessing)?
    public var fastVLMService: (any FastVLMAnalyzing)?
    
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
    
    // MARK: - AsyncStream-based Progress Delivery
    
    /// Stream of queue progress events. Subscribe with `for await event in service.progressStream`.
    /// The stream is long-lived and emits events for each queue processing cycle.
    public var progressStream: AsyncStream<QueueProgressEvent> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }
    
    /// Active continuation for the progress stream.
    private var progressContinuation: AsyncStream<QueueProgressEvent>.Continuation?
    
    private func emitProgress(_ event: QueueProgressEvent) {
        progressContinuation?.yield(event)
    }
    
    private var currentTask: Task<Void, Never>?
    private var queueGeneration: Int = 0

    public init(
        queueStore: DiverQueueStore,
        modelContainer: ModelContainer,
        mainContext: ModelContext,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,

        indexingService: KnowledgeGraphIndexingService? = nil,
        contextService: (any ContextProcessing)? = nil
    ) {
        self.queueStore = queueStore
        self.modelContainer = modelContainer
        self.modelContext = mainContext
        self.enrichmentService = enrichmentService
        self.locationService = locationService

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
        emitProgress(.cancelled)
        // Unload FastVLM from GPU — dispatched to background to avoid blocking main thread
        // during GPU resource deallocation. Metal buffers are invalidated in background.
        fastVLMService?.retainModel = false
        Task.detached(priority: .background) { [fastVLMService] in
            fastVLMService?.unloadModel()
        }
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
        let bgTaskHolder = await MainActor.run { () -> BackgroundTaskHolder in
            let holder = BackgroundTaskHolder()
            holder.taskID = UIApplication.shared.beginBackgroundTask(withName: "DiverMetadataPipeline") { [self] in
                // iOS is about to kill us — cancel GPU/ML work immediately
                self.cancelProcessing()
                UIApplication.shared.endBackgroundTask(holder.taskID)
                holder.taskID = .invalid
            }
            return holder
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

            // Create a background ModelContext so SwiftData operations
            // don't serialize through the main queue and block the UI.
            let bgCtx = ModelContext(self.modelContainer)
            bgCtx.autosaveEnabled = false
            self.bgContext = bgCtx
            defer { self.bgContext = nil }

            // Show progress immediately
            self.isProcessingQueue = true
            self.queueTotalCount = 0
            self.queueCompletedCount = 0
            self.queueCurrentItemTitle = nil
            self.queueStatusMessage = "Checking queue…"
            self.emitProgress(.started(totalCount: 0))

            do {
                // 1. Resume any stuck items from previous sessions (DB persistence)
                DiverLogger.queue.debug("Checking for stuck items or pending database transactions...")
                self.fastVLMService?.retainModel = true
                try await self.resumeSuspendedQueue()
                if Task.isCancelled { 
                    DiverLogger.queue.debug("Queue processing cancelled after resumeSuspendedQueue")
                    if self.queueGeneration == myGeneration {
                        self.resetQueueProgress()
                    }
                    return 
                }

                // 2. Process disk queue records (shared links from DiverQueueStore)
                let records = try self.queueStore.pendingEntries()
                if !records.isEmpty {
                    print("🔄 [MetadataPipeline] Processing \(records.count) entries from disk...")
                    DiverLogger.queue.info("Processing \(records.count) pending queue entries from disk")
                    
                    self.queueTotalCount += records.count

                    var successCount = 0
                    var errorCount = 0

                    for record in records {
                        if Task.isCancelled { break }
                        await Task.yield() // Let main actor service UI events between items
                        
                        let itemTitle = record.item.descriptor.title
                        self.queueCurrentItemTitle = itemTitle
                        self.queueStatusMessage = "Processing shared link…"
                        self.emitProgress(.processingItem(
                            completedCount: self.queueCompletedCount,
                            totalCount: self.queueTotalCount,
                            itemTitle: itemTitle,
                            statusMessage: "Processing shared link…"
                        ))
                        
                        do {
                            print("📦 [MetadataPipeline] Starting: \(record.item.id)")
                            try await self.handle(record: record)
                            try await self.saveWithRetry()
                            try self.queueStore.remove(record)
                            successCount += 1
                            self.queueCompletedCount += 1
                            self.emitProgress(.itemCompleted(
                                completedCount: self.queueCompletedCount,
                                totalCount: self.queueTotalCount
                            ))
                            print("✅ [MetadataPipeline] Finished: \(record.item.id)")
                            DiverLogger.queue.debug("Successfully processed and persisted queue item: \(record.item.id)")
                        } catch {
                            errorCount += 1
                            print("❌ [MetadataPipeline] Failed \(record.fileURL.lastPathComponent): \(error)")
                            DiverLogger.queue.logError(error, context: "Error processing record \(record.fileURL.lastPathComponent)")
                            try? await self.handleFailure(record: record, error: error)
                            try? await self.saveWithRetry()
                            try? self.queueStore.remove(record)
                            self.queueCompletedCount += 1
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
                self.fastVLMService?.retainModel = false
                if self.queueGeneration == myGeneration {
                    self.resetQueueProgress()
                }
                
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                DiverLogger.queue.error("Queue processing failed: \(error)")
                self.fastVLMService?.retainModel = false
                if self.queueGeneration == myGeneration {
                    self.resetQueueProgress()
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
                try activeContext.save()
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
        
        guard let localItem = try activeContext.fetch(fetchDescriptor).first else {
            print("❌ processItemImmediately: Could not find item \(itemID) in pipeline context")
            throw NSError(domain: "MetadataPipelineService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Item not found"])
        }
        
        localItem.statusRaw = ProcessingStatus.processing.rawValue
        localItem.updatedAt = Date() // CRITICAL: Update timestamp to prevent zombie check from marking as stalled
        localItem.processingLog.append("\(Date().formatted()): Starting high-priority 'Process Now' workflow.")
        try? activeContext.save()
        
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
                input = try? activeContext.fetch(urlFetch).first
            }
            
            if input == nil, let title = targetTitle {
                let titleFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.text == title })
                input = try? activeContext.fetch(titleFetch).first
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
                let sessionFetch = FetchDescriptor<SessionMetadata>(
                    predicate: #Predicate { $0.sessionID == sessionID }
                )
                if let session = try? activeContext.fetch(sessionFetch).first {
                    session.summary = nil
                    session.updatedAt = Date()
                    localItem.processingLog.append("\(Date().formatted()): Cleared parent session summary for regeneration.")
                }
            }
            
            try? activeContext.save()
            
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
                 
                 activeContext.insert(fallbackInput)
                 _ = try await localPipeline.process(
                    input: fallbackInput,
                    descriptor: descriptor,
                    enrichmentService: enrichmentService,
                    locationService: effectiveLocationService,
                    indexingService: indexingService,
                    contextService: contextService
                )
            }
            
            // Mark as ready if processing succeeded
            // CRITICAL: Set statusRaw directly (not through @Transient status) to ensure SwiftData persistence
            localItem.statusRaw = ProcessingStatus.ready.rawValue
            localItem.processingLog.append("\(Date().formatted()): Processing completed successfully.")
            try activeContext.save()
            
            // Ingest into CLaRa's in-memory document index for immediate RAG searchability
            CLaRaLatentService.shared.ingestProcessedItem(
                id: localItem.id,
                title: localItem.title,
                summary: localItem.summary,
                transcription: localItem.transcription,
                tags: localItem.tags,
                visualTags: localItem.visualTags,
                categories: localItem.categories,
                location: localItem.location,
                purposes: localItem.purposes,
                productMetadata: localItem.productMetadata,
                url: localItem.url,
                placeContextData: localItem.placeContextData,
                webContextData: localItem.webContextData,
                weatherContextData: localItem.weatherContextData,
                documentContextData: localItem.documentContextData,
                qrContextData: localItem.qrContextData,
                fastVLMAnalysisData: localItem.fastVLMAnalysisData,
                questions: localItem.questions
            )
            
        } catch {
            // Handle errors - don't leave item stuck in processing state
            localItem.statusRaw = ProcessingStatus.failed.rawValue
            localItem.failureCount += 1
            localItem.processingLog.append("\(Date().formatted()): Processing failed - \(error.localizedDescription)")
            try? activeContext.save()
            print("❌ processItemImmediately failed: \(error)")
            throw error
        }
        
        // Restart the rest of the queue in background
        Task {
            try? await self.processPendingQueue()
        }
    }
    
    /// Process a single item by ID using a **private** ModelContext.
    /// Safe to call from any isolation context — does not share state with  
    /// the service's `activeContext`. Use this instead of `processItemImmediately`
    /// when triggering reprocessing from UI code (e.g., after a location edit).
    public func processItemByID(_ itemID: String) async throws {
        let bgCtx = ModelContext(modelContainer)
        bgCtx.autosaveEnabled = false
        
        let fetchDescriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        
        guard let localItem = try bgCtx.fetch(fetchDescriptor).first else {
            print("❌ processItemByID: Could not find item \(itemID)")
            return
        }
        
        localItem.statusRaw = ProcessingStatus.processing.rawValue
        localItem.updatedAt = Date()
        localItem.processingLog.append("\(Date().formatted()): Starting reprocessing via processItemByID.")
        try? bgCtx.save()
        
        do {
            let localPipeline = LocalPipelineService(modelContext: bgCtx)
            
            // Detect user-set location (same logic as processItemImmediately)
            let hasUserSetLocation: Bool = {
                guard let placeContext = localItem.placeContext else { return false }
                if placeContext.contactIdentifier != nil { return true }
                if let placeID = placeContext.placeID {
                    if placeID.hasPrefix("mapkit-") || placeID.hasPrefix("mk-") || placeID == "home-location" {
                        return true
                    }
                }
                return false
            }()
            
            let effectiveLocationService = hasUserSetLocation ? nil : locationService
            
            // Clear calculated data for fresh reprocessing
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
            
            // Clear parent session summary
            if let sessionID = localItem.sessionID {
                let sessionFetch = FetchDescriptor<SessionMetadata>(
                    predicate: #Predicate { $0.sessionID == sessionID }
                )
                if let session = try? bgCtx.fetch(sessionFetch).first {
                    session.summary = nil
                    session.updatedAt = Date()
                }
            }
            
            try? bgCtx.save()
            
            let descriptor = DiverItemDescriptor(
                id: localItem.id,
                url: localItem.url ?? "",
                title: localItem.title ?? "",
                type: DiverItemType(rawValue: localItem.entityType ?? "web") ?? .web,
                attributionID: localItem.attributionID,
                masterCaptureID: localItem.masterCaptureID,
                sessionID: localItem.sessionID
            )
            
            // Find or create LocalInput
            var input: LocalInput?
            
            if let url = localItem.url {
                let urlFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.url == url })
                input = try? bgCtx.fetch(urlFetch).first
            }
            
            if input == nil, let title = localItem.title {
                let titleFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.text == title })
                input = try? bgCtx.fetch(titleFetch).first
            }
            
            if let input = input {
                _ = try await localPipeline.process(
                    input: input,
                    descriptor: descriptor,
                    enrichmentService: enrichmentService,
                    locationService: effectiveLocationService,
                    indexingService: indexingService,
                    contextService: contextService
                )
            } else {
                var imageData: Data? = localItem.rawPayload
                if imageData == nil, let assetId = localItem.photosAssetIdentifier {
                    imageData = await PhotosAssetLoader.shared.loadImageData(identifier: assetId)
                }
                
                let fallbackInput = LocalInput(
                    createdAt: localItem.createdAt,
                    url: localItem.url,
                    text: localItem.title,
                    source: localItem.source ?? "reprocessing",
                    inputType: localItem.entityType ?? "web",
                    rawPayload: imageData
                )
                
                bgCtx.insert(fallbackInput)
                _ = try await localPipeline.process(
                    input: fallbackInput,
                    descriptor: descriptor,
                    enrichmentService: enrichmentService,
                    locationService: effectiveLocationService,
                    indexingService: indexingService,
                    contextService: contextService
                )
            }
            
            localItem.statusRaw = ProcessingStatus.ready.rawValue
            localItem.processingLog.append("\(Date().formatted()): Reprocessing completed successfully.")
            try bgCtx.save()
            
            // Ingest into CLaRa's in-memory document index for immediate RAG searchability
            CLaRaLatentService.shared.ingestProcessedItem(
                id: localItem.id,
                title: localItem.title,
                summary: localItem.summary,
                transcription: localItem.transcription,
                tags: localItem.tags,
                visualTags: localItem.visualTags,
                categories: localItem.categories,
                location: localItem.location,
                purposes: localItem.purposes,
                productMetadata: localItem.productMetadata,
                url: localItem.url,
                placeContextData: localItem.placeContextData,
                webContextData: localItem.webContextData,
                weatherContextData: localItem.weatherContextData,
                documentContextData: localItem.documentContextData,
                qrContextData: localItem.qrContextData,
                fastVLMAnalysisData: localItem.fastVLMAnalysisData,
                questions: localItem.questions
            )
            
        } catch {
            localItem.statusRaw = ProcessingStatus.failed.rawValue
            localItem.failureCount += 1
            localItem.processingLog.append("\(Date().formatted()): Reprocessing failed - \(error.localizedDescription)")
            try? bgCtx.save()
            print("❌ processItemByID failed for \(itemID): \(error)")
            throw error
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
        let stuckItems = try activeContext.fetch(processingFetch)
        
        if !stuckItems.isEmpty {
            DiverLogger.pipeline.warning("Found \(stuckItems.count) stuck items in processing state for >5 mins. Resetting to queued.")
            for item in stuckItems {
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): Resumed from stalled state (timeout)")
            }
            try activeContext.save()
        }
        
        // 2. Process all persistent LocalInputs (Pending Work)
        // LocalInput is only deleted upon successful completion of LocalPipelineService.process
        let inputFetch = FetchDescriptor<LocalInput>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let pendingInputs = try activeContext.fetch(inputFetch)
        
        if !pendingInputs.isEmpty {
            DiverLogger.pipeline.info("Resuming \(pendingInputs.count) pending transactions from database")
            
            // Add to running total
            queueTotalCount += pendingInputs.count
            queueStatusMessage = "Resuming interrupted items…"
            
            let localPipeline = LocalPipelineService(modelContext: activeContext)
            
            for input in pendingInputs {
                do {
                    // Yield to main actor between items so UI remains responsive
                    await Task.yield()
                    // CRITICAL FIX: Skip LocalInputs that already have a fully processed item
                    // This prevents reprocessing items that completed successfully but whose
                    // LocalInput deletion was interrupted (crash, timing issue)
                    let inputId = input.id.uuidString
                    let checkFetch = FetchDescriptor<ProcessedItem>(
                        predicate: #Predicate { $0.inputId == inputId && $0.statusRaw == "ready" }
                    )
                    if let existingReady = try? activeContext.fetch(checkFetch).first {
                        DiverLogger.pipeline.debug("Skipping already-completed input \(inputId) - ProcessedItem \(existingReady.id) is ready")
                        // Clean up the orphaned LocalInput
                        activeContext.delete(input)
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

                        indexingService: self.indexingService,
                        contextService: self.contextService,
                        fastVLMService: self.fastVLMService
                    )
                    queueCompletedCount += 1
                } catch {
                    DiverLogger.pipeline.error("Failed to resume input \(input.id): \(error)")
                    queueCompletedCount += 1
                }
            }
            try activeContext.save()
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
        
        guard let queuedItems = try? activeContext.fetch(queuedFetch), !queuedItems.isEmpty else {
            return
        }
        
        DiverLogger.pipeline.info("Processing \(queuedItems.count) queued items without LocalInput")
        
        // Add to running total (parent already set isProcessingQueue = true)
        queueTotalCount += queuedItems.count
        
        for item in queuedItems {
            if Task.isCancelled { break }
            await Task.yield() // Let main actor service UI events between items
            
            // Check if there's already a LocalInput for this item
            let itemURL = item.url
            let urlFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.url == itemURL })
            if let _ = try? activeContext.fetch(urlFetch).first {
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
                try? activeContext.save()
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
        
        guard let queuedItems = try? activeContext.fetch(queuedFetch), !queuedItems.isEmpty else {
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
                try? activeContext.save()
                
                let localInput = LocalInput(
                    createdAt: item.createdAt,
                    url: nil,
                    source: "photoLibraryImport",
                    inputType: item.mediaType ?? "image",
                    rawPayload: imageData
                )
                
                activeContext.insert(localInput)
                
                let localPipeline = LocalPipelineService(modelContext: activeContext)
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
                
                // Cache descriptor for crash recovery (matches handle(record:) pattern)
                localInput.descriptorJSON = try? JSONEncoder().encode(descriptor)
                
                // Save checkpoint: ensures LocalInput + descriptorJSON survive a crash
                try? activeContext.save()
                
                queueStatusMessage = "Running pipeline…"
                _ = try await localPipeline.process(
                    input: localInput,
                    descriptor: descriptor,
                    enrichmentService: self.enrichmentService,
                    locationService: nil,

                    indexingService: self.indexingService,
                    contextService: self.contextService,
                    fastVLMService: self.fastVLMService
                )
                
                try? activeContext.save()
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
        
        try? activeContext.save()
        print("📸 [MetadataPipeline] PHAsset processing complete. Success: \(successCount), Failed: \(errorCount)")
    }
    
    /// Clears queue progress state after a brief delay so the "complete" state is visible.
    private func resetQueueProgress() {
        queueCurrentItemTitle = nil
        queueStatusMessage = "Complete"
        emitProgress(.completed(totalCount: queueTotalCount))
        resetTask?.cancel()
        resetTask = Task { [weak self] in
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
        print("💾 [DIAG] handle(record:): descriptor.sessionID=\(descriptor.sessionID ?? "NIL"), localInput.sessionID=\(localInput.sessionID ?? "NIL"), purposes=\(descriptor.purposes)")
        // Persist full descriptor for crash recovery — if the task is cancelled
        // before process() completes, resumeSuspendedQueue can recover it.
        localInput.descriptorJSON = try? JSONEncoder().encode(descriptor)

        activeContext.insert(localInput)
        // CRITICAL: Save immediately so LocalInput (with descriptorJSON containing sessionID)
        // survives a crash. Without this, resumeSuspendedQueue can't recover the session ID.
        try? activeContext.save()
        let localPipeline = LocalPipelineService(modelContext: activeContext)
        
        // For photo library imports, pass nil for locationService to prevent GPS override
        // The descriptor already contains the photo's original location
        let useLocationService = record.item.source != "photoLibraryImport" ? locationService : nil
        
        let processedItem = try await localPipeline.process(
            input: localInput,
            descriptor: descriptor,
            enrichmentService: enrichmentService,
            locationService: useLocationService,

            indexingService: indexingService,
            contextService: contextService,
            fastVLMService: fastVLMService
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
        let localPipeline = LocalPipelineService(modelContext: activeContext)
        try await localPipeline.refreshProcessedItems(
            enrichmentService: enrichmentService,
            locationService: locationService,

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
        
        if let existing = try? activeContext.fetch(fetch).first {
            existing.failureCount += 1
            existing.processingLog.append("\(Date().formatted()): Failure (\(existing.failureCount)): \(error.localizedDescription)")
            
            if existing.failureCount > 2 {
                DiverLogger.pipeline.warning("Item \(id) failed too many times. Deleting.")
                activeContext.delete(existing)
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
            activeContext.insert(failedItem)
            
            // CRITICAL: Ensure even failed items have a session so they aren't orphaned in UI
            let localPipeline = LocalPipelineService(modelContext: activeContext)
            await localPipeline.syncSession(for: failedItem)
            
            DiverLogger.pipeline.error("Created failed item \(id) due to: \(error)")
        }
        try activeContext.save()
    }
    public func runDataDiagnostics() async {
        let localPipeline = LocalPipelineService(modelContext: activeContext)
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
            let sessionDescriptor = FetchDescriptor<SessionMetadata>(
                predicate: #Predicate { $0.summary == nil }
            )
            let sessions = try activeContext.fetch(sessionDescriptor)
            
            print("🔄 [MetadataPipeline] Found \(sessions.count) sessions needing summaries")
            
            for session in sessions {
                // Fetch all items for this session
                let sessionID = session.sessionID
                let itemDescriptor = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.sessionID == sessionID },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                
                guard let items = try? activeContext.fetch(itemDescriptor), !items.isEmpty else {
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
                    
                    llmSummary = "Session with \(count) items. Includes: \(titles.isEmpty ? "Captured content" : titles). [Model: Heuristic Fallback]"
                }
                
                session.summary = llmSummary
                session.updatedAt = Date()
                
                print("✅ [MetadataPipeline] Generated summary for session '\(session.sessionID)': \(llmSummary.prefix(100))...")
            }
            
            try activeContext.save()
            
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
            let collectionDescriptor = FetchDescriptor<SessionCollection>(
                predicate: #Predicate { $0.llmSummary == nil }
            )
            let collections = try activeContext.fetch(collectionDescriptor)
            
            for collection in collections {
                // Fetch items for this collection's sessions
                var allItems: [ProcessedItem] = []
                
                for sessionID in collection.sessionIDs {
                    let itemDescriptor = FetchDescriptor<ProcessedItem>(
                        predicate: #Predicate { $0.sessionID == sessionID }
                    )
                    if let items = try? activeContext.fetch(itemDescriptor) {
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
                    summary = "Collection containing \(count) items. Includes: \(examples.isEmpty ? "Various items" : examples). [Model: Heuristic Fallback]"
                }
                
                collection.llmSummary = summary
                collection.updatedAt = Date()
                
                print("✅ [MetadataPipeline] Generated summary for collection '\(collection.name)'")
            }
            
            try activeContext.save()
            
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
