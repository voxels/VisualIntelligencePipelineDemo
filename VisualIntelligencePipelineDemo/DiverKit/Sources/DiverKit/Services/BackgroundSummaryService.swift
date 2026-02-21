//
//  BackgroundSummaryService.swift
//  DiverKit
//
//  Monitors for an active Edge Connection and silently upgrades 
//  `[Model: SystemLanguageModel-iOS26]` summaries to `[Model: Edge-MLX-CLaRa]` ones.
//

import Foundation
import SwiftData

/// Non-blocking actor that silently upgrades local LLM summaries using the Edge node.
public actor BackgroundSummaryService {
    
    public static let shared = BackgroundSummaryService()
    private var currentTask: Task<Void, Never>?
    
    public init() {}
    
    /// Starts the background upgrade process if an Edge node is available and we aren't already running.
    public func startUpgradesIfNeeded(modelContainer: ModelContainer, router: PipelineEdgeRouter, system: VisualIntelligenceActorSystem) {
        guard currentTask == nil else { return }
        
        currentTask = Task.detached(priority: .background) {
            let decision = await router.shouldOffload(task: .vlmInference)
            guard case .edge(let node, _) = decision else {
                await self.clearTask()
                return
            }
            
            print("🔄 [BackgroundSummaryService] Edge node '\(node.deviceName)' detected. Starting silent summary upgrades...")
            
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            
            do {
                try await self.upgradeProcessedItems(modelContext: context, nodeName: node.deviceName, system: system)
                guard !Task.isCancelled else {
                    await self.clearTask()
                    return
                }
                try await self.upgradeSessions(modelContext: context, nodeName: node.deviceName, system: system)
            } catch {
                if Task.isCancelled {
                    print("🛑 [BackgroundSummaryService] Upgrade cycle cancelled (Edge unavailable).")
                } else {
                    print("❌ [BackgroundSummaryService] Upgrade cycle failed: \(error)")
                }
            }
            
            await self.clearTask()
        }
    }
    
    public func cancelUpgrades() {
        currentTask?.cancel()
        currentTask = nil
        print("🛑 [BackgroundSummaryService] Cancelling background upgrades...")
    }
    
    private func clearTask() {
        self.currentTask = nil
    }
    
    private func upgradeProcessedItems(modelContext: ModelContext, nodeName: String, system: VisualIntelligenceActorSystem) async throws {
        // Find ProcessedItems with the old model tag or heuristic fallback
        // We use predicate string matching so SQLite filters it natively
        var descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { item in
                if let summary = item.summary {
                    return summary.contains("[Model: SystemLanguageModel-iOS26]") || summary.contains("[Model: Heuristic Fallback]")
                } else {
                    return false
                }
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        
        let itemsToUpgrade = try modelContext.fetch(descriptor)
        
        guard !itemsToUpgrade.isEmpty else { return }
        
        let identity = EdgeActorID(id: "EdgeContext", nodeName: nodeName)
        let edgeActor = try EdgeContextActor.resolve(id: identity, using: system)
        
        for item in itemsToUpgrade {
            guard let oldSummary = item.summary, !Task.isCancelled else { continue }
            print("🧠 [BackgroundSummaryService] Upgrading ProcessedItem summary for \(item.id)...")
            
            do {
                var contextParts: [String] = []
                if let t = item.title { contextParts.append("Title: \(t)") }
                if let o = item.transcription { contextParts.append("OCR: \(o.prefix(500))") }
                if let p = item.placeContext?.name { contextParts.append("Venue: \(p)") }
                
                let textToSummarize: String
                if !contextParts.isEmpty {
                    textToSummarize = contextParts.joined(separator: "\n")
                } else {
                    textToSummarize = "Rewrite the following into a very concise 1-sentence activity description: \(oldSummary)"
                }
                
                var attempt = 1
                var success = false
                while attempt <= 3 && !success && !Task.isCancelled {
                    do {
                        let newSummary = try await edgeActor.summarize(text: textToSummarize)
                        if !Task.isCancelled {
                            item.summary = newSummary
                            item.updatedAt = Date()
                            item.processingLog.append("\(Date().formatted()): Summary silently upgraded by Edge Context Actor")
                            try modelContext.save()
                            print("🌟 [BackgroundSummaryService] Successfully upgraded ProcessedItem \(item.id)")
                            success = true
                            // Pacing to avoid overwhelming the edge processor
                            try await Task.sleep(for: .seconds(2))
                        }
                    } catch {
                        print("⚠️ [BackgroundSummaryService] Attempt \(attempt) failed for item \(item.id): \(error)")
                        attempt += 1
                        if attempt <= 3 {
                            // Exponential-ish backoff
                            try await Task.sleep(for: .seconds(Double(attempt * 2)))
                        }
                    }
                }
        }
    }
    
        var descriptor = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate { session in
                if let summary = session.summary {
                    return summary.contains("[Model: SystemLanguageModel-iOS26]") || summary.contains("[Model: Heuristic Fallback]")
                } else {
                    return false
                }
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        
        let sessionsToUpgrade = try modelContext.fetch(descriptor)
        
        guard !sessionsToUpgrade.isEmpty else { return }
        
        let identity = EdgeActorID(id: "EdgeContext", nodeName: nodeName)
        let edgeActor = try EdgeContextActor.resolve(id: identity, using: system)
        
        for session in sessionsToUpgrade {
            guard let oldSummary = session.summary, !Task.isCancelled else { continue }
            print("🧠 [BackgroundSummaryService] Upgrading Session summary for \(session.sessionID)...")
            
            do {
                let sid = session.sessionID
                let itemDesc = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sid })
                let items = try modelContext.fetch(itemDesc)
                
                let contextParts = items.compactMap { $0.title }.joined(separator: ", ")
                let textToSummarize: String
                if !contextParts.isEmpty {
                    textToSummarize = "Session at \(session.locationName ?? "Unknown") containing items: \(contextParts)"
                } else {
                    textToSummarize = "Summarize this session concisely: \(oldSummary)"
                }
                
                var attempt = 1
                var success = false
                while attempt <= 3 && !success && !Task.isCancelled {
                    do {
                        let newSummary = try await edgeActor.summarize(text: textToSummarize)
                        if !Task.isCancelled {
                            session.summary = newSummary
                            session.updatedAt = Date()
                            try modelContext.save()
                            print("🌟 [BackgroundSummaryService] Successfully upgraded Session \(session.sessionID)")
                            success = true
                            // Pacing to avoid overwhelming the edge processor
                            try await Task.sleep(for: .seconds(2))
                        }
                    } catch {
                        print("⚠️ [BackgroundSummaryService] Attempt \(attempt) failed for session \(session.sessionID): \(error)")
                        attempt += 1
                        if attempt <= 3 {
                            try await Task.sleep(for: .seconds(Double(attempt * 2)))
                        }
                    }
                }
            } catch {
                print("⚠️ [BackgroundSummaryService] Failed to upgrade session \(session.sessionID): \(error)")
            }
        }
    }
}
