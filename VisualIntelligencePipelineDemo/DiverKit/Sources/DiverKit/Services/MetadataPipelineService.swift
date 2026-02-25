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

@MainActor
@Observable
public final class MetadataPipelineService {
    private let orchestrator: MetadataPipelineOrchestrator
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    // MARK: - Queue Progress (observed by UI)
    public var isProcessingQueue: Bool = false
    public var queueTotalCount: Int = 0
    public var queueCompletedCount: Int = 0
    public var queueCurrentItemTitle: String? = nil
    public var queueStatusMessage: String? = nil
    
    public var queueProgress: Double {
        guard queueTotalCount > 0 else { return 0 }
        return Double(queueCompletedCount) / Double(queueTotalCount)
    }
    
    private var progressContinuation: AsyncStream<QueueProgressEvent>.Continuation?
    
    public var progressStream: AsyncStream<QueueProgressEvent> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }
    
    private var progressTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    public init(
        queueStore: DiverQueueStore?,
        modelContainer: ModelContainer,
        mainContext: ModelContext,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil,
        contextService: (any ContextProcessing)? = nil,
        fastVLMService: (any FastVLMAnalyzing)? = nil
    ) {
        self.modelContainer = modelContainer
        self.modelContext = mainContext
        self.orchestrator = MetadataPipelineOrchestrator(
            modelContainer: modelContainer,
            queueStore: queueStore,
            enrichmentService: enrichmentService,
            locationService: locationService,
            indexingService: indexingService,
            contextService: contextService,
            fastVLMService: fastVLMService
        )
        
        // Start listening to progress updates
        self.startObservingOrchestrator()
    }
    
    private func startObservingOrchestrator() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            for await event in (await self?.orchestrator.progressStream ?? AsyncStream<QueueProgressEvent> { $0.finish() }) {
                guard let self else { return }
                self.handleProgressEvent(event)
            }
        }
    }
    
    private func handleProgressEvent(_ event: QueueProgressEvent) {
        progressContinuation?.yield(event)
        switch event {
        case .started(let totalCount):
            self.isProcessingQueue = true
            self.queueTotalCount = totalCount
            self.queueCompletedCount = 0
            self.queueStatusMessage = "Starting..."
            
        case .processingItem(let completed, let total, let title, let status):
            self.isProcessingQueue = true
            self.queueCompletedCount = completed
            self.queueTotalCount = total
            self.queueCurrentItemTitle = title
            self.queueStatusMessage = status
            
        case .itemCompleted(let completed, let total):
            self.queueCompletedCount = completed
            self.queueTotalCount = total
            
        case .completed(let total):
            self.queueTotalCount = total
            self.queueCompletedCount = total
            self.resetQueueProgress()
            
        case .cancelled:
            self.isProcessingQueue = false
            self.queueStatusMessage = "Cancelled"
        }
    }
    
    private func resetQueueProgress() {
        queueCurrentItemTitle = nil
        queueStatusMessage = "Complete"
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard !Task.isCancelled else { return }
            self.isProcessingQueue = false
            self.queueTotalCount = 0
            self.queueCompletedCount = 0
            self.queueStatusMessage = nil
        }
    }
    
    // MARK: - Public API (Delegates to Orchestrator)
    
    public func processPendingQueue() async throws {
        #if os(iOS)
        let holder = BackgroundTaskHolder()
        holder.taskID = UIApplication.shared.beginBackgroundTask(withName: "DiverMetadataPipeline") { [weak self] in
            Task { @MainActor in
                self?.cancelProcessing()
                if holder.taskID != .invalid {
                    UIApplication.shared.endBackgroundTask(holder.taskID)
                    holder.taskID = .invalid
                }
            }
        }
        
        defer {
            if holder.taskID != .invalid {
                UIApplication.shared.endBackgroundTask(holder.taskID)
            }
        }
        #endif
        
        await orchestrator.processPendingQueue()
    }
    
    public func cancelProcessing() {
        Task {
            await orchestrator.cancelProcessing()
        }
        isProcessingQueue = false
        queueTotalCount = 0
        queueCompletedCount = 0
        queueCurrentItemTitle = nil
        queueStatusMessage = nil
    }
    
    public func processItemImmediately(_ item: ProcessedItem) async throws {
        // High priority: cancel current queue
        await orchestrator.cancelProcessing()
        
        // Process this item specifically
        try await orchestrator.processItemByID(item.id, force: true)
        
        // Resume queue in background
        Task {
            try? await self.processPendingQueue()
        }
    }
    
    public func processItemByID(_ itemID: String, force: Bool = false) async throws {
        try await orchestrator.processItemByID(itemID, force: force)
    }
    
    public func refreshProcessedItems() async throws {
        try await orchestrator.refreshProcessedItems()
    }

    // MARK: - Service Injection Forwarding
    
    public var enrichmentService: LinkEnrichmentService? {
        get { nil } // Not directly readable from actor without async
        set {
            Task {
                await orchestrator.setEnrichmentService(newValue)
            }
        }
    }

    public var locationService: LocationProvider? {
        get { nil }
        set {
            Task {
                await orchestrator.setLocationService(newValue)
            }
        }
    }

    public var indexingService: KnowledgeGraphIndexingService? {
        get { nil }
        set {
            Task {
                await orchestrator.setIndexingService(newValue)
            }
        }
    }

    public var contextService: (any ContextProcessing)? {
        get { nil }
        set {
            Task {
                await orchestrator.setContextService(newValue)
            }
        }
    }

    public var fastVLMService: (any FastVLMAnalyzing)? {
        get { nil }
        set {
            Task {
                await orchestrator.setFastVLMService(newValue)
            }
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
