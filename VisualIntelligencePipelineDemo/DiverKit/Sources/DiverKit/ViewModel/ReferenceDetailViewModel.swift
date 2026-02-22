//
//  ReferenceDetailViewModel.swift
//  DiverKit
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import SwiftData
import DiverShared
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Lightweight view-safe struct for score history chart data.
public struct ScoreSnapshotData: Identifiable, Sendable {
    public var id: String { "\(strategyID)-\(date.timeIntervalSince1970)" }
    public let date: Date
    public let score: Double
    public let strategyID: String
    
    public init(date: Date, score: Double, strategyID: String) {
        self.date = date
        self.score = score
        self.strategyID = strategyID
    }
}

@MainActor
public class ReferenceDetailViewModel: ObservableObject {
    
    public init() {}
    
    @Published public var suggestedPurposes: [String] = []
    @Published public var isGeneratingPurposes: Bool = false
    
    // MARK: - Actions
    
    public func generatePurposes(for item: ProcessedItem, siblingContext: String) {
        guard !isGeneratingPurposes else { return }
        isGeneratingPurposes = true
        
        Task {
            do {
                if let service = Services.shared.contextQuestionService {
                    // Build structured context in priority order (VISUAL → WEB → PLACE → ENVIRONMENT)
                    var contextParts: [String] = []
                    
                    // === ITEM IDENTITY (PRIMARY) ===
                    contextParts.append("=== FOCUS ITEM ===")
                    if let title = item.title { contextParts.append("Title: \(title)") }
                    if let summary = item.summary { contextParts.append("Summary: \(summary)") }
                    
                    // === VISUAL/OCR CONTENT ===
                    if let transcription = item.transcription, !transcription.isEmpty {
                        contextParts.append("OCR/Captured Text: \(String(transcription.prefix(300)))")
                    }
                    
                    // === WEB CONTENT ===
                    if let webContent = item.webContext?.textContent, !webContent.isEmpty {
                        contextParts.append("Web Content: \(String(webContent.prefix(300)))")
                    }
                    if let structured = item.webContext?.structuredData {
                        contextParts.append("Structured Data: \(structured)")
                    }
                    
                    // === PLACE DETAILS ===
                    if let placeName = item.placeContext?.name {
                        contextParts.append("Place: \(placeName)")
                    }
                    if let tips = item.placeContext?.tips, !tips.isEmpty {
                        contextParts.append("Place Tips: \(tips.prefix(2).joined(separator: "; "))")
                    }
                    
                    // === ENVIRONMENT ===
                    if let weather = item.weatherContext {
                        contextParts.append("Weather: \(weather.condition), \(Int(weather.temperatureCelsius))°C")
                    }
                    if let activity = item.activityContext {
                        contextParts.append("Activity: \(activity.type)")
                    }
                    
                    // === EXISTING TAGS ===
                    if !item.tags.isEmpty {
                        contextParts.append("Tags: \(item.tags.joined(separator: ", "))")
                    }
                    
                    // === SESSION CONTEXT ===
                    if !siblingContext.isEmpty {
                        contextParts.append("\n=== SESSION CONTEXT ===\n\(siblingContext)")
                    }
                    
                    let fullContext = contextParts.joined(separator: "\n")
                    
                    print("🔍 ReferenceDetailViewModel: Requesting purposes for item '\(item.title ?? "Untitled")'")
                    let suggestions = try await service.suggestPurposes(from: fullContext)
                    
                    await MainActor.run {
                        // Filter out purposes already present in the item and ensure uniqueness
                        let currentPurposes = Set(item.purposes)
                        var seen = Set<String>()
                        let uniqueSuggestions = suggestions.filter { seen.insert($0).inserted }
                        self.suggestedPurposes = uniqueSuggestions.filter { !currentPurposes.contains($0) }
                        
                        self.isGeneratingPurposes = false
                        print("✅ ReferenceDetailViewModel: Received \(suggestions.count) suggestions, \(self.suggestedPurposes.count) new")
                    }
                } else {
                    print("❌ ReferenceDetailViewModel: ContextQuestionService not found")
                    await MainActor.run { self.isGeneratingPurposes = false }
                }
            } catch {
                print("❌ ReferenceDetailViewModel: Failed to generate purposes: \(error)")
                await MainActor.run { self.isGeneratingPurposes = false }
            }
        }
    }
    
    // MARK: - Purpose Management
    
    public func addPurpose(_ purpose: String, to item: ProcessedItem) {
        Task { @MainActor in
            guard !item.purposes.contains(purpose) else { return }
            
            withAnimation {
                item.purposes.append(purpose)
            }
            try? item.modelContext?.save()
            
            // Remove from suggestions if present
            if let idx = self.suggestedPurposes.firstIndex(of: purpose) {
                _ = withAnimation {
                    self.suggestedPurposes.remove(at: idx)
                }
            }
            
            // Auto-regenerate summary to reflect new purpose
            if let service = Services.shared.localPipelineService {
                print("🔄 Regenerating summary for purpose update...")
                await service.regenerateSummary(for: item)
            }
        }
    }
    
    public func removePurpose(_ purpose: String, from item: ProcessedItem) {
        // Mutate immediately for instant UI feedback
        if let index = item.purposes.firstIndex(of: purpose) {
            _ = withAnimation {
                item.purposes.remove(at: index)
            }
            // Defer save so the animation isn't blocked
            Task { @MainActor in
                try? item.modelContext?.save()
            }
        }
    }
    
    public func removeSemanticTag(_ tag: String, from item: ProcessedItem) {
        // Mutate immediately for instant UI feedback
        var changed = false
        
        if let idx = item.purposes.firstIndex(of: tag) {
            item.purposes.remove(at: idx)
            changed = true
        }
        if let idx = item.tags.firstIndex(of: tag) {
            item.tags.remove(at: idx)
            changed = true
        }
        if let idx = item.visualTags.firstIndex(of: tag) {
            item.visualTags.remove(at: idx)
            changed = true
        }
        if let idx = item.categories.firstIndex(of: tag) {
            item.categories.remove(at: idx)
            changed = true
        }
        
        if changed {
            // Defer save so the animation isn't blocked
            Task { @MainActor in
                try? item.modelContext?.save()
            }
        }
    }
    
    public func updateTitle(_ title: String, for item: ProcessedItem) {
        Task { @MainActor in
            // Basic validation
             guard title.count > 2, !title.contains("http"), title != item.title else { return }
            
             item.title = title
             try? item.modelContext?.save()
             
             // Regenerate summary to reflect new title
             if let service = Services.shared.localPipelineService {
                 print("🔄 Regenerating summary after title update...")
                 await service.regenerateSummary(for: item)
             }
        }
    }
    
    public func retryProcessing(item: ProcessedItem) {
        // Use ID from item if available, or generate from URL
        let itemId = UUID(uuidString: item.id) ?? UUID()
        let urlString = item.url ?? "" // Allow empty URL if it's an image capture
        
        // checking entity type
        let typeRaw = item.entityType ?? "web"
        let type = DiverItemType(rawValue: typeRaw) ?? .web

        let descriptor = DiverItemDescriptor(
            id: itemId.uuidString,
            url: urlString,
            title: item.title ?? "Untitled",
            descriptionText: item.summary,
            styleTags: [],
            categories: ["retry"],
            location: item.location,
            price: item.price,
            type: type,
            attributionID: item.attributionID,
            masterCaptureID: item.masterCaptureID,
            sessionID: item.sessionID,
            purposes: Set(item.purposes)
        )

        Task {
            do {
                // Determine payload - load from Photos library if needed
                var payload = item.rawPayload
                
                // If no rawPayload but has photosAssetIdentifier, load on-demand
                if payload == nil, let assetId = item.photosAssetIdentifier {
                    print("📸 Loading image data from Photos library for reprocessing: \(assetId)")
                    payload = await PhotosAssetLoader.shared.loadImageData(identifier: assetId)
                    if payload != nil {
                        print("✅ Loaded \(payload!.count) bytes from Photos library")
                    } else {
                        print("⚠️ Failed to load data from Photos library - asset may have been deleted")
                    }
                }
                
                let queueItem = DiverQueueItem(
                    id: UUID(), // New queue entry
                    action: "save",
                    descriptor: descriptor,
                    source: "retry",
                    createdAt: Date(), // Fresh timestamp
                    payload: payload
                )
                
                let queueDirectory = AppGroupContainer.queueDirectoryURL()!
                let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
                _ = try queueStore.enqueue(queueItem)
                print("✅ Re-enqueued item for deep processing: \(urlString) (Payload: \(payload?.count ?? 0) bytes)")
                
                // Update UI state
                await MainActor.run {
                    item.status = .queued
                }
            } catch {
                print("❌ Failed to re-enqueue item: \(error)")
            }
        }
    }
    
    public func refreshLinkMetadata(item: ProcessedItem) {
        print("🔄 ReferenceDetailViewModel: User requested immediate link refresh for \(item.id)")
        
        // Immediate visual feedback
        item.status = .processing
        
        let itemID = item.id
        Task.detached(priority: .utility) {
            do {
                if let pipeline = await MainActor.run(body: { Services.shared.metadataPipelineService }) {
                    try await pipeline.processItemByID(itemID)
                    print("✅ Immediate refresh completed for \(itemID)")
                    // Update the main-context item status — processItemByID writes to a
                    // private background ModelContext, so the main-context copy stays stale.
                    await MainActor.run { item.status = .ready }
                } else {
                    print("❌ MetadataPipelineService not available")
                    await MainActor.run { item.status = .failed }
                }
            } catch {
                print("❌ Failed to trigger immediate refresh: \(error)")
                await MainActor.run { item.status = .failed }
            }
        }
    }
    
    public func openOriginalURL(item: ProcessedItem) {
        if let urlString = item.url, let url = URL(string: urlString) {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
    
    // MARK: - Score History
    
    @Published public var scoreSnapshots: [ScoreSnapshotData] = []
    
    /// Fetches ScoreSnapshot records for a product and maps to chart-ready data.
    /// Uses DiverPersistenceActor for proper actor-isolated SwiftData access.
    public func fetchScoreHistory(productID: String) {
        guard let container = Services.shared.modelContext?.container else { return }
        
        Task.detached(priority: .utility) { [weak self] in
            let actor = PersistenceActor(modelContainer: container)
            let data = (try? await actor.fetchScoreHistory(productID: productID)) ?? []
            
            await MainActor.run { [weak self] in
                self?.scoreSnapshots = data
            }
        }
    }
}
