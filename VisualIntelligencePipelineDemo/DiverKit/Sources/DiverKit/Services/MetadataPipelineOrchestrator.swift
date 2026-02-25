import Foundation
import SwiftData
import DiverShared
import os
import WidgetKit
#if os(iOS)
import UIKit
#endif

/// Actor responsible for the heavy lifting of metadata processing.
/// Isolated to a background execution context to keep the Main Actor responsive.
public actor MetadataPipelineOrchestrator {
    private let modelContainer: ModelContainer
    private let queueStore: DiverQueueStore?
    
    // Services (retained for the life of the orchestrator)
    private var enrichmentService: LinkEnrichmentService?
    private var locationService: LocationProvider?
    private var indexingService: KnowledgeGraphIndexingService?
    private var contextService: (any ContextProcessing)?
    private var fastVLMService: (any FastVLMAnalyzing)?
    
    // MARK: - Progress Streaming
    private var progressContinuation: AsyncStream<QueueProgressEvent>.Continuation?
    
    // MARK: - State Tracking
    private var isProcessingQueue: Bool = false
    private var queueTotalCount: Int = 0
    private var queueCompletedCount: Int = 0
    private var currentTask: Task<Void, Never>?
    private var queueGeneration: Int = 0

    public init(
        modelContainer: ModelContainer,
        queueStore: DiverQueueStore?,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil,
        contextService: (any ContextProcessing)? = nil,
        fastVLMService: (any FastVLMAnalyzing)? = nil
    ) {
        self.modelContainer = modelContainer
        self.queueStore = queueStore
        self.enrichmentService = enrichmentService
        self.locationService = locationService
        self.indexingService = indexingService
        self.contextService = contextService
        self.fastVLMService = fastVLMService
    }

    public func setEnrichmentService(_ service: LinkEnrichmentService?) {
        self.enrichmentService = service
    }

    public func setLocationService(_ service: LocationProvider?) {
        self.locationService = service
    }

    public func setIndexingService(_ service: KnowledgeGraphIndexingService?) {
        self.indexingService = service
    }

    public func setContextService(_ service: (any ContextProcessing)?) {
        self.contextService = service
    }

    public func setFastVLMService(_ service: (any FastVLMAnalyzing)?) {
        self.fastVLMService = service
    }
    
    /// Stream of progress events emitted during processing.
    public var progressStream: AsyncStream<QueueProgressEvent> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }
    
    private func emit(_ event: QueueProgressEvent) {
        progressContinuation?.yield(event)
    }

    /// Primary entry point for processing the background queue.
    public func processPendingQueue() async {
        // Cancel any existing task
        currentTask?.cancel()
        
        guard let queueStore = self.queueStore else {
            DiverLogger.queue.error("Queue process aborted: DriverQueueStore is nil")
            return
        }
        
        queueGeneration += 1
        let myGeneration = queueGeneration
        
        // Start processing task
        let task = Task(priority: .utility) {
            let bgContext = ModelContext(modelContainer)
            bgContext.autosaveEnabled = false
            
            // Initial progress
            self.isProcessingQueue = true
            self.queueTotalCount = 0
            self.queueCompletedCount = 0
            self.emit(.started(totalCount: 0))
            
            do {
                // 1. Resume any stuck items from previous sessions
                try await self.resumeSuspendedQueue(context: bgContext)
                
                guard !Task.isCancelled else { return }
                
                // 2. Process disk queue records
                let records = try queueStore.pendingEntries()
                if !records.isEmpty {
                    self.queueTotalCount += records.count
                    
                    for record in records {
                        guard !Task.isCancelled else { break }
                        
                        let itemTitle = record.item.descriptor.title
                        self.emit(.processingItem(
                            completedCount: self.queueCompletedCount,
                            totalCount: self.queueTotalCount,
                            itemTitle: itemTitle,
                            statusMessage: "Processing shared link..."
                        ))
                        
                        do {
                            try await self.handle(record: record, context: bgContext)
                            try await self.saveWithRetry(context: bgContext)
                            try? queueStore.remove(record)
                            
                            self.queueCompletedCount += 1
                            self.emit(.itemCompleted(
                                completedCount: self.queueCompletedCount,
                                totalCount: self.queueTotalCount
                            ))
                        } catch {
                            DiverLogger.queue.error("Failed to process record \(record.item.id): \(error)")
                            // Handle failure and continue
                            try? await self.handleFailure(record: record, error: error, context: bgContext)
                            try? await self.saveWithRetry(context: bgContext)
                            try? queueStore.remove(record)
                            self.queueCompletedCount += 1
                        }
                    }
                    
                    // Post-processing batches
                    await self.generatePendingSessionSummaries(context: bgContext)
                    await self.generatePendingCollectionSummaries(context: bgContext)
                    await self.enrichCapturedItems(context: bgContext)
                }
                
                if myGeneration == self.queueGeneration {
                    self.emit(.completed(totalCount: self.queueTotalCount))
                    self.isProcessingQueue = false
                }
                
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                DiverLogger.queue.error("Queue processing failed: \(error)")
                if myGeneration == self.queueGeneration {
                    self.emit(.completed(totalCount: self.queueTotalCount))
                    self.isProcessingQueue = false
                }
            }
        }
        
        currentTask = task
        _ = await task.result // Wait for completion
    }

    /// Process a single item by ID.
    public func processItemByID(_ itemID: String, force: Bool = false) async throws {
        let bgCtx = ModelContext(modelContainer)
        bgCtx.autosaveEnabled = false
        
        let fetchDescriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        
        guard let localItem = try bgCtx.fetch(fetchDescriptor).first else {
            DiverLogger.pipeline.error("processItemByID: Could not find item \(itemID)")
            return
        }
        
        if !force {
            let currentStatus = ProcessingStatus(rawValue: localItem.statusRaw) ?? .queued
            if currentStatus == .ready || currentStatus == .processing {
                DiverLogger.pipeline.debug("processItemByID: Skipping \(itemID) - already \(localItem.statusRaw)")
                return
            }
        }
        
        localItem.status = .processing
        localItem.updatedAt = Date()
        
        // Add audit log for freshness guard tests
        let logEntry = "[\(Date())] Starting reprocessing via processItemByID (force: \(force))"
        localItem.processingLog.append(logEntry)
        
        try? bgCtx.save()
        
        do {
            let localPipeline = LocalPipelineService(modelContext: bgCtx)
            
            // Clear calculated data
            localItem.summary = nil
            localItem.transcription = nil
            localItem.tags = []
            localItem.purposes = []
            localItem.categories = []
            localItem.questions = []
            
            // Determine if we should preserve location
            let hasUserSetLocation = self.hasUserSetLocation(localItem)
            if !hasUserSetLocation {
                localItem.placeContextData = nil
            }
            
            let effectiveLocationService = hasUserSetLocation ? nil : locationService
            
            // Run processing
            let input = try self.findOrCreateLocalInput(for: localItem, context: bgCtx)
            let descriptor = self.createDescriptor(from: localItem)
            
            _ = try await localPipeline.process(
                input: input,
                descriptor: descriptor,
                enrichmentService: enrichmentService,
                locationService: effectiveLocationService,
                indexingService: indexingService,
                contextService: contextService,
                fastVLMService: fastVLMService,
                scoringStrategies: self.defaultScoringStrategies(),
                recommender: self.defaultRecommender()
            )
            
            localItem.status = .ready
            try bgCtx.save()
            
            self.ingestIntoCLaRa(localItem)
        } catch {
            localItem.status = .failed
            localItem.failureCount += 1
            try? bgCtx.save()
            throw error
        }
    }
    
    public func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
        isProcessingQueue = false
        emit(.cancelled)
        
        // Unload models
        Task.detached(priority: .background) { [fastVLMService] in
            fastVLMService?.unloadModel()
        }
    }

    public func runDataDiagnostics() async {
        let bgCtx = ModelContext(modelContainer)
        let localPipeline = LocalPipelineService(modelContext: bgCtx)
        await localPipeline.runDataDiagnostics()
    }
    
    public func refreshProcessedItems() async throws {
        let bgCtx = ModelContext(modelContainer)
        let localPipeline = LocalPipelineService(modelContext: bgCtx)
        try await localPipeline.refreshProcessedItems(
            enrichmentService: enrichmentService,
            locationService: locationService,
            indexingService: indexingService
        )
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Private Helpers (Migrated from MetadataPipelineService)
    
    private func resumeSuspendedQueue(context: ModelContext) async throws {
        // Reset stuck items
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let processingFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "processing" && $0.updatedAt < fiveMinutesAgo }
        )
        let stuckItems = try context.fetch(processingFetch)
        for item in stuckItems {
            item.status = .queued
        }
        try context.save()
        
        // Process pending LocalInputs
        let inputFetch = FetchDescriptor<LocalInput>(sortBy: [SortDescriptor(\.createdAt)])
        let pendingInputs = try context.fetch(inputFetch)
        
        if !pendingInputs.isEmpty {
            self.queueTotalCount += pendingInputs.count
            let localPipeline = LocalPipelineService(modelContext: context)
            
            for input in pendingInputs {
                guard !Task.isCancelled else { break }
                
                // Skip if already ready
                let inputId = input.id.uuidString
                let checkFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.inputId == inputId && $0.statusRaw == "ready" })
                if let _ = try? context.fetch(checkFetch).first {
                    context.delete(input)
                    self.queueTotalCount -= 1
                    continue
                }
                
                let recoveredDescriptor = self.recoverDescriptor(from: input)
                
                _ = try await localPipeline.process(
                    input: input,
                    descriptor: recoveredDescriptor,
                    enrichmentService: enrichmentService,
                    locationService: locationService,
                    indexingService: indexingService,
                    contextService: contextService,
                    fastVLMService: fastVLMService,
                    scoringStrategies: self.defaultScoringStrategies(),
                    recommender: self.defaultRecommender()
                )
                self.queueCompletedCount += 1
            }
            try context.save()
        }
        
        // Orphaned items and PHAsset items
        await self.processQueuedOrphanItems(context: context)
        await self.processImportedPHAssetItems(context: context)
    }
    
    private func handle(record: DiverQueueRecord, context: ModelContext) async throws {
        let descriptor = record.item.descriptor
        var payload = record.item.payload
        
        if payload == nil, let assetIdentifier = record.item.photosAssetIdentifier {
            payload = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetIdentifier)
        }
        
        let localInput = LocalInput(
            createdAt: record.item.createdAt,
            url: descriptor.url,
            source: record.item.source,
            inputType: descriptor.type.rawValue,
            rawPayload: payload,
            sessionID: descriptor.sessionID,
            purposes: Array(descriptor.purposes)
        )
        localInput.descriptorJSON = try? JSONEncoder().encode(descriptor)
        context.insert(localInput)
        try? context.save()
        
        let localPipeline = LocalPipelineService(modelContext: context)
        let useLocationService = record.item.source != "photoLibraryImport" ? locationService : nil
        
        let processedItem = try await localPipeline.process(
            input: localInput,
            descriptor: descriptor,
            enrichmentService: enrichmentService,
            locationService: useLocationService,
            indexingService: indexingService,
            contextService: contextService,
            fastVLMService: fastVLMService,
            scoringStrategies: self.defaultScoringStrategies(),
            recommender: self.defaultRecommender(),
            captureOnly: true
        )
        
        if let depthData = record.item.depthPayload {
            processedItem.depthPayload = depthData
        }
    }
    
    private func enrichCapturedItems(context: ModelContext) async {
        let capturedStatus = ProcessingStatus.captured.rawValue
        let capturedFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == capturedStatus },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        guard let capturedItems = try? context.fetch(capturedFetch), !capturedItems.isEmpty else { return }
        
        for item in capturedItems {
            guard !Task.isCancelled else { break }
            item.status = .enriching
            try? context.save()
            
            do {
                let localPipeline = LocalPipelineService(modelContext: context)
                let enrichInput = LocalInput(
                    createdAt: item.createdAt,
                    url: item.url,
                    text: item.title,
                    source: item.source ?? "enrichment",
                    inputType: item.entityType ?? "web",
                    rawPayload: item.rawPayload
                )
                context.insert(enrichInput)
                
                let descriptor = self.createDescriptor(from: item)
                
                _ = try await localPipeline.process(
                    input: enrichInput,
                    descriptor: descriptor,
                    enrichmentService: enrichmentService,
                    locationService: nil,
                    indexingService: indexingService,
                    contextService: contextService,
                    fastVLMService: fastVLMService,
                    scoringStrategies: self.defaultScoringStrategies(),
                    recommender: self.defaultRecommender(),
                    captureOnly: false
                )
                
                item.status = .ready
                try? context.save()
                self.ingestIntoCLaRa(item)
            } catch {
                item.status = .failed
                try? context.save()
            }
        }
    }

    private func handleFailure(record: DiverQueueRecord, error: Error, context: ModelContext) async throws {
        let descriptor = record.item.descriptor
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == descriptor.id })
        
        if let existing = try? context.fetch(fetch).first {
            existing.failureCount += 1
            if existing.failureCount > 2 {
                context.delete(existing)
            } else {
                existing.status = .failed
            }
        } else {
            let failedItem = ProcessedItem(
                id: descriptor.id,
                url: descriptor.url,
                title: descriptor.title,
                summary: "Failed: \(error.localizedDescription)",
                entityType: descriptor.type.rawValue,
                status: .failed,
                source: record.item.source,
                sessionID: descriptor.sessionID,
                failureCount: 1
            )
            context.insert(failedItem)
            let localPipeline = LocalPipelineService(modelContext: context)
            await localPipeline.syncSession(for: failedItem)
        }
    }
    
    private func processQueuedOrphanItems(context: ModelContext) async {
        let queuedFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "queued" && $0.source != "photoLibraryImport" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let queuedItems = try? context.fetch(queuedFetch) else { return }
        self.queueTotalCount += queuedItems.count
        
        for item in queuedItems {
            guard !Task.isCancelled else { break }
            do {
                try await self.processItemByID(item.id)
            } catch {
                item.status = .failed
                try? context.save()
            }
            self.queueCompletedCount += 1
        }
    }
    
    private func processImportedPHAssetItems(context: ModelContext) async {
        let queuedFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.statusRaw == "queued" && $0.source == "photoLibraryImport" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let queuedItems = try? context.fetch(queuedFetch) else { return }
        self.queueTotalCount += queuedItems.count
        
        for item in queuedItems {
            guard !Task.isCancelled else { break }
            guard let assetIdentifier = item.photosAssetIdentifier else {
                item.status = .failed
                self.queueCompletedCount += 1
                continue
            }
            
            if let imageData = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetIdentifier) {
                do {
                    item.status = .processing
                    let localInput = LocalInput(
                        createdAt: item.createdAt,
                        url: nil,
                        source: "photoLibraryImport",
                        inputType: item.mediaType ?? "image",
                        rawPayload: imageData
                    )
                    context.insert(localInput)
                    
                    let localPipeline = LocalPipelineService(modelContext: context)
                    let descriptor = self.createDescriptor(from: item)
                    localInput.descriptorJSON = try? JSONEncoder().encode(descriptor)
                    try? context.save()
                    
                    _ = try await localPipeline.process(
                        input: localInput,
                        descriptor: descriptor,
                        enrichmentService: enrichmentService,
                        locationService: nil,
                        indexingService: indexingService,
                        contextService: contextService,
                        fastVLMService: fastVLMService,
                        scoringStrategies: self.defaultScoringStrategies(),
                        recommender: self.defaultRecommender()
                    )
                } catch {
                    item.status = .failed
                }
            } else {
                item.status = .failed
            }
            self.queueCompletedCount += 1
        }
        try? context.save()
    }

    private func saveWithRetry(context: ModelContext, attempts: Int = 3) async throws {
        for i in 0..<attempts {
            do {
                try context.save()
                return
            } catch {
                if i == attempts - 1 { throw error }
                try? await Task.sleep(nanoseconds: UInt64(200_000_000 * (i + 1)))
            }
        }
    }

    private func hasUserSetLocation(_ item: ProcessedItem) -> Bool {
        guard let placeContext = item.placeContext else { return false }
        if placeContext.contactIdentifier != nil { return true }
        if let placeID = placeContext.placeID {
            if placeID.hasPrefix("mapkit-") || placeID.hasPrefix("mk-") || placeID == "home-location" {
                return true
            }
        }
        return false
    }
    
    private func createDescriptor(from item: ProcessedItem) -> DiverItemDescriptor {
        DiverItemDescriptor(
            id: item.id,
            url: item.url ?? "",
            title: item.title ?? "",
            type: DiverItemType(rawValue: item.entityType ?? "web") ?? .web,
            attributionID: item.attributionID,
            masterCaptureID: item.masterCaptureID,
            sessionID: item.sessionID
        )
    }
    
    private func findOrCreateLocalInput(for item: ProcessedItem, context: ModelContext) throws -> LocalInput {
        if let url = item.url {
            let urlFetch = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.url == url })
            if let existing = try? context.fetch(urlFetch).first { return existing }
        }
        
        let input = LocalInput(
            createdAt: item.createdAt,
            url: item.url,
            text: item.title,
            source: item.source ?? "reprocessing",
            inputType: item.entityType ?? "web",
            rawPayload: item.rawPayload
        )
        context.insert(input)
        return input
    }
    
    private func recoverDescriptor(from input: LocalInput) -> DiverItemDescriptor? {
        guard let json = input.descriptorJSON else { return nil }
        return try? JSONDecoder().decode(DiverItemDescriptor.self, from: json)
    }
    
    private func ingestIntoCLaRa(_ item: ProcessedItem) {
        CLaRaLatentService.shared.ingestProcessedItem(
            id: item.id,
            title: item.title,
            summary: item.summary,
            transcription: item.transcription,
            tags: item.tags,
            visualTags: item.visualTags,
            categories: item.categories,
            location: item.location,
            purposes: item.purposes,
            productMetadata: item.productMetadata,
            url: item.url,
            placeContextData: item.placeContextData,
            webContextData: item.webContextData,
            weatherContextData: item.weatherContextData,
            documentContextData: item.documentContextData,
            qrContextData: item.qrContextData,
            fastVLMAnalysisData: item.fastVLMAnalysisData,
            questions: item.questions
        )
    }
    
    private func defaultScoringStrategies() -> [any ProductScoringStrategy] {
        [
            ESGScoringStrategy(),
            BrandAlignmentStrategy(),
            ValueScoringStrategy(),
            DurabilityScoringStrategy(),
            SocialProofScoringStrategy(),
            HealthFitScoringStrategy(),
            TotalCostScoringStrategy()
        ]
    }
    
    private func defaultRecommender() -> any ProductRecommending {
        ProductRecommendationService()
    }

    // MARK: - Summary Generation
    
    private func generatePendingSessionSummaries(context: ModelContext) async {
        guard let contextService else { return }
        do {
            let sessionDescriptor = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.summary == nil })
            let sessions = try context.fetch(sessionDescriptor)
            
            for session in sessions {
                let sessionID = session.sessionID
                let itemDescriptor = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.sessionID == sessionID },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                
                guard let items = try? context.fetch(itemDescriptor), !items.isEmpty else { continue }
                
                let itemContexts = items.compactMap { item -> String? in
                    var parts: [String] = []
                    if let title = item.title, !title.isEmpty { parts.append("Title: \(title)") }
                    if let transcription = item.transcription, !transcription.isEmpty {
                        parts.append("OCR: \(transcription.prefix(300))")
                    }
                    if !item.tags.isEmpty { parts.append("Tags: \(item.tags.joined(separator: ", "))") }
                    if let mt = item.mediaType { parts.append("Media Type: \(mt)") }
                    if let p = item.placeContext {
                        if let name = p.name { parts.append("Venue: \(name)") }
                    }
                    return parts.isEmpty ? nil : parts.joined(separator: " | ")
                }.prefix(20)
                
                guard !itemContexts.isEmpty else { continue }
                
                let contextText = """
                Session with \(items.count) captures.
                
                Captured items:
                \(Array(itemContexts).joined(separator: "\n"))
                """
                
                let summary = try await contextService.summarizeText(contextText)
                session.summary = summary
                session.updatedAt = Date()
            }
            try context.save()
        } catch {
            DiverLogger.pipeline.error("Failed to generate session summaries: \(error)")
        }
    }
    
    private func generatePendingCollectionSummaries(context: ModelContext) async {
        guard let contextService else { return }
        do {
            let collectionDescriptor = FetchDescriptor<SessionCollection>(predicate: #Predicate { $0.llmSummary == nil })
            let collections = try context.fetch(collectionDescriptor)
            
            for collection in collections {
                var allItems: [ProcessedItem] = []
                for sessionID in collection.sessionIDs {
                    let itemDescriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sessionID })
                    if let items = try? context.fetch(itemDescriptor) {
                        allItems.append(contentsOf: items)
                    }
                }
                
                guard !allItems.isEmpty else { continue }
                
                let itemSummaries = allItems.compactMap { item -> String? in
                    var parts: [String] = []
                    if let title = item.title { parts.append(title) }
                    if let summary = item.summary { parts.append(summary) }
                    return parts.isEmpty ? nil : parts.joined(separator: ": ")
                }.prefix(50)
                
                let contextText = "Collection: \(collection.name)\n\nItems:\n" + Array(itemSummaries).joined(separator: "\n")
                let summary = try await contextService.summarizeText(contextText)
                collection.llmSummary = summary
                collection.updatedAt = Date()
            }
            try context.save()
        } catch {
            DiverLogger.pipeline.error("Failed to generate collection summaries: \(error)")
        }
    }
}
