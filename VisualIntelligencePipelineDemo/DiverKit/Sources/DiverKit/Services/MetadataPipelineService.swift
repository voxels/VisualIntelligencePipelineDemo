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
        #if os(iOS)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
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

        // 1. Resume any stuck items from previous sessions (DB persistence)
        try? await resumeSuspendedQueue()

        let records = try queueStore.pendingEntries()
        if !records.isEmpty {
            DiverLogger.queue.info("Processing \(records.count) pending queue entries")
        }

        var successCount = 0
        var errorCount = 0

        for record in records {
            do {
                try await handle(record: record)
                try queueStore.remove(record)
                successCount += 1
                DiverLogger.queue.debug("Successfully processed queue item: \(record.item.id)")
            } catch {
                errorCount += 1
                DiverLogger.queue.logError(error, context: "Error processing record \(record.fileURL.lastPathComponent)")
                
                // Keep the manual call to handleFailure if it's new logic, or ensure it's integrated
                // Based on previous file read, it seems user might have added it but let's confirm integration.
                try? await handleFailure(record: record, error: error)

                // Remove from queue - standard behavior
                try? queueStore.remove(record)
                continue
            }
        }

        DiverLogger.queue.info("Queue processing complete - success: \(successCount), failed: \(errorCount), total: \(records.count)")
        
        // Refresh all widgets after processing
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Resumes processing for items that may have been interrupted (app termination, crash)
    private func resumeSuspendedQueue() async throws {
        // 1. Reset "Processing" -> "Queued" (Zombie Check)
        let processingFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "processing" }
        )
        let stuckItems = try modelContext.fetch(processingFetch)
        
        if !stuckItems.isEmpty {
            DiverLogger.pipeline.warning("Found \(stuckItems.count) stuck items in processing state. Resetting to queued.")
            for item in stuckItems {
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): Resumed from stalled state")
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
                        enrichmentService: enrichmentService,
                        locationService: locationService,
                        foursquareService: foursquareService,
                        duckDuckGoService: duckDuckGoService,
                        weatherService: weatherService,
                        activityService: activityService,
                        indexingService: indexingService,
                        contextService: contextService
                    )
                } catch {
                    DiverLogger.pipeline.error("Failed to resume input \(input.id): \(error)")
                    // If it fails repeatedly, we might want to flag the associated item as failed
                    // But for now, we leave it to retry or stay pending
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
            existing.status = .failed
            DiverLogger.pipeline.error("Marked item \(id) as failed due to: \(error)")
        } else {
            // Create a failed placeholder if it doesn't exist (so user can see it and retry)
            let failedItem = ProcessedItem(
                id: id,
                url: descriptor.url,
                title: descriptor.title ?? "Processing Failed",
                summary: "Failed to process: \(error.localizedDescription)",
                entityType: descriptor.type.rawValue,
                status: .failed,
                source: record.item.source,
                attributionID: descriptor.attributionID
            )
            modelContext.insert(failedItem)
            DiverLogger.pipeline.error("Created failed item \(id) due to: \(error)")
        }
        try modelContext.save()
    }
}
