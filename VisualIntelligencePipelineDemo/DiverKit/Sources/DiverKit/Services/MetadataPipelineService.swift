import Foundation
import SwiftData
import DiverShared
import WidgetKit
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
    public var activityService: ActivityEnrichmentService?
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
        activityService: ActivityEnrichmentService? = nil,
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
        self.activityService = activityService
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
                        try queueStore.remove(record)
                        successCount += 1
                        print("✅ [MetadataPipeline] Finished: \(record.item.id)")
                        DiverLogger.queue.debug("Successfully processed queue item: \(record.item.id)")
                    } catch {
                        errorCount += 1
                        print("❌ [MetadataPipeline] Failed \(record.fileURL.lastPathComponent): \(error)")
                        DiverLogger.queue.logError(error, context: "Error processing record \(record.fileURL.lastPathComponent)")
                        
                        try? await handleFailure(record: record, error: error)
                        try? queueStore.remove(record)
                        continue
                    }
                }

                print("🏁 [MetadataPipeline] Complete. Success: \(successCount), Failed: \(errorCount)")
                DiverLogger.queue.info("Queue processing complete - success: \(successCount), failed: \(errorCount), total: \(records.count)")
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                DiverLogger.queue.error("Queue processing failed: \(error)")
            }
        }
        
        self.currentTask = task
        _ = await task.result
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
                activityService: activityService,
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
                activityService: activityService,
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
                    // Re-run process. logic checks for existing items automatically.
                    _ = try await localPipeline.process(
                        input: input,
                        enrichmentService: self.enrichmentService,
                        locationService: self.locationService,
                        foursquareService: self.foursquareService,
                        duckDuckGoService: self.duckDuckGoService,
                        weatherService: self.weatherService,
                        activityService: self.activityService,
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
    }

    private func handle(record: DiverQueueRecord) async throws {
        let descriptor = record.item.descriptor

        DiverLogger.pipeline.debug("Creating LocalInput from descriptor - url: \(descriptor.url), type: \(descriptor.type.rawValue), attributionID: \(descriptor.attributionID ?? "nil")")

        let localInput = LocalInput(
            url: descriptor.url,
            source: record.item.source,
            inputType: descriptor.type.rawValue,
            rawPayload: record.item.payload
        )

        modelContext.insert(localInput)
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        _ = try await localPipeline.process(
            input: localInput,
            descriptor: descriptor,
            enrichmentService: enrichmentService,
            locationService: locationService,
            foursquareService: foursquareService,
            duckDuckGoService: duckDuckGoService,
            weatherService: weatherService,
            activityService: activityService,
            indexingService: indexingService,
            contextService: contextService
        )
        try modelContext.save()

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
            activityService: activityService,
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
