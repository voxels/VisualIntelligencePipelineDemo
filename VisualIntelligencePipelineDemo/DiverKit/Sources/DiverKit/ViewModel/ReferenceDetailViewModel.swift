//
//  ReferenceDetailViewModel.swift
//  DiverKit
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import DiverShared
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        
        Task {
            do {
                if let pipeline = Services.shared.metadataPipelineService {
                    try await pipeline.processItemImmediately(item)
                    print("✅ Immediate refresh triggered via PipelineService")
                    
                    // Optimistic UI update
                    await MainActor.run {
                        item.status = .processing
                    }
                } else {
                    print("❌ MetadataPipelineService not available")
                }
            } catch {
                print("❌ Failed to trigger immediate refresh: \(error)")
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
}
