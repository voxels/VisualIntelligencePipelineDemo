//
//  SharedWithYouManager.swift
//  Diver
//
//  Manages Shared with You highlights from Messages
//

import Foundation
import SharedWithYou
import DiverShared
import DiverKit
import OSLog
import SwiftData

#if os(iOS)
import UIKit
#endif

/// Manages Shared with You integration to ingest links shared via Messages
@available(iOS 16.0, macOS 13.0, *)
@MainActor
class SharedWithYouManager: NSObject, ObservableObject {

    private let logger = Logger(subsystem: DiverLogger.subsystem, category: "shared-with-you")
    private let queueStore: DiverQueueStore
    private let pipelineService: MetadataPipelineService?
    private let highlightCenter: SWHighlightCenter

    @Published private(set) var highlights: [SWHighlight] = []
    @Published private(set) var isEnabled: Bool

    /// Initialize the manager with a queue store for enqueueing shared content
    init(queueStore: DiverQueueStore, pipelineService: MetadataPipelineService? = nil, isEnabled: Bool = true) {
        self.queueStore = queueStore
        self.pipelineService = pipelineService
        self.isEnabled = isEnabled
        self.highlightCenter = SWHighlightCenter()
        super.init()

        if isEnabled {
            setupHighlightObservation()
        }
    }

    /// Start observing highlights from Messages
    private func setupHighlightObservation() {
        // Observe highlights from the highlight center
        highlightCenter.delegate = self

        // Fetch initial highlights
        refreshHighlights()

        logger.info("Shared with You manager initialized and observing highlights")
    }

    /// Refresh the list of highlights
    func refreshHighlights() {
        Task { @MainActor in
            let fetchedHighlights = highlightCenter.highlights
            self.highlights = fetchedHighlights
            logger.debug("Refreshed highlights: \(fetchedHighlights.count) items")
        }
    }

    /// Process a highlight and enqueue it for processing
    func processHighlight(_ highlight: SWHighlight, sessionID: String? = nil) async throws {
        guard isEnabled else {
            logger.warning("Attempted to process highlight while Shared with You is disabled")
            return
        }

        // Extract URL from highlight
        guard let url = extractURL(from: highlight) else {
            logger.error("Failed to extract URL from highlight: \(String(describing: highlight.identifier))")
            return
        }

        // Validate URL
        guard Validation.isValidURL(url.absoluteString) else {
            logger.warning("Invalid URL from highlight: \(url.absoluteString)")
            return
        }

        // Create descriptor - DiverItemDescriptor requires id and url at minimum
        let itemId = DiverLinkWrapper.id(for: url)
        let attributionID = String(describing:highlight.identifier)
        logger.debug("🔎 [SharedWithYou] Processing highlight: \(url.absoluteString), attributionID: \(attributionID)")
        
        let descriptor = DiverItemDescriptor(
            id: itemId,
            url: url.absoluteString,
            title: extractTitle(from: highlight) ?? "Shared Link",
            descriptionText: nil,
            styleTags: [],
            categories: [],
            type: .web,
            attributionID: attributionID,
            sessionID: sessionID
        )

        // Create queue item and enqueue for processing
        let queueItem = DiverQueueItem(action: "process", descriptor: descriptor, source: "shared_with_you")

        do {
            let record = try queueStore.enqueue(queueItem)
            logger.info("Enqueued highlight: \(url.absoluteString) (record: \(record.item.id))")
            
            // Trigger immediate processing so it shows up in the sidebar
            if let pipelineService {
                try await pipelineService.processPendingQueue()
            }
        } catch {
            logger.error("Failed to enqueue highlight: \(error.localizedDescription)")
            throw error
        }
    }

    /// Extract URL from a highlight
    private func extractURL(from highlight: SWHighlight) -> URL? {
        // SWHighlight.url property contains the shared URL
        return highlight.url
    }

    /// Extract title from highlight metadata
    private func extractTitle(from highlight: SWHighlight) -> String? {
        // Use the URL as a basic title if no other metadata is available
        let url = highlight.url
        return url.host ?? url.absoluteString
    }

    /// Toggle Shared with You feature on/off
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        if enabled {
            setupHighlightObservation()
        } else {
            highlightCenter.delegate = nil
            highlights = []
        }

        logger.info("Shared with You \(enabled ? "enabled" : "disabled")")
    }

    /// Find a highlight by its identifier string
    func findHighlight(id: String) -> SWHighlight? {
        return highlights.first(where: { String(describing:$0.identifier) == id })
    }

    /// Process all highlights that haven't been imported yet
    func processUnprocessedHighlights(modelContext: ModelContext) async {
        guard isEnabled else { return }
        
        let currentHighlights = highlightCenter.highlights
        if currentHighlights.isEmpty {
            logger.info("No shared highlights found to process")
            return
        }
        
        // Fetch existing attribution IDs to avoid duplicates
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.attributionID != nil }
        )
        
        do {
            let existingItems = try modelContext.fetch(fetch)
            let existingIDs = Set(existingItems.compactMap { $0.attributionID })
            
            logger.info("Found \(existingIDs.count) existing attributed items. Checking \(currentHighlights.count) highlights.")
            
            let batchSessionID = UUID().uuidString
            
            var processedCount = 0
            for highlight in currentHighlights {
                let id = String(describing: highlight.identifier)
                if !existingIDs.contains(id) {
                    try? await processHighlight(highlight, sessionID: batchSessionID)
                    processedCount += 1
                }
            }
            
            if processedCount > 0 {
                logger.info("Automatically enqueued \(processedCount) new shared links")
            } else {
                logger.info("No new shared links to process")
            }
            
        } catch {
            logger.error("Failed to fetch existing items for de-duplication: \(error)")
        }
    }
}

// MARK: - SWHighlightCenterDelegate

@available(iOS 16.0, macOS 13.0, *)
extension SharedWithYouManager: SWHighlightCenterDelegate {

    nonisolated func highlightCenterHighlightsDidChange(_ highlightCenter: SWHighlightCenter) {
        Task { @MainActor in
            logger.debug("Highlights changed notification received")
            refreshHighlights()
        }
    }
}
