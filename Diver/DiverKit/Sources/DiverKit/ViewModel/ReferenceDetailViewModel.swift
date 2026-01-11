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
                    // Combine item context with sibling context
                    let itemContext = [item.title, item.summary, item.tags.joined(separator: ", ")].compactMap { $0 }.joined(separator: "\n")
                    let fullContext = "Focus Item:\n\(itemContext)\n\nSession Context:\n\(siblingContext)"
                    
                    let suggestions = try await service.suggestPurposes(from: fullContext)
                    
                    await MainActor.run {
                        self.suggestedPurposes = suggestions
                        self.isGeneratingPurposes = false
                    }
                } else {
                    await MainActor.run { self.isGeneratingPurposes = false }
                }
            } catch {
                print("Failed to generate purposes: \(error)")
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
            purposes: item.purposes
        )

        Task {
            do {
                // Pass rawPayload (original image/data) to queue item to ensure deep reprocessing
                let queueItem = DiverQueueItem(
                    id: UUID(), // New queue entry
                    action: "save",
                    descriptor: descriptor,
                    source: "retry",
                    createdAt: Date(), // Fresh timestamp
                    payload: item.rawPayload
                )
                
                let queueDirectory = AppGroupContainer.queueDirectoryURL()!
                let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
                _ = try queueStore.enqueue(queueItem)
                print("✅ Re-enqueued item for deep processing: \(urlString) (Payload: \(item.rawPayload?.count ?? 0) bytes)")
                
                // Update UI state
                await MainActor.run {
                    item.status = .queued
                }
            } catch {
                print("❌ Failed to re-enqueue item: \(error)")
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
