//
//  AgenticSearchService.swift
//  DiverKit
//
//  Client-side wrapper that uses the PipelineEdgeRouter to discover an EdgeDaemon
//  and send CLaRa Agentic Search payloads/queries over the Distributed Actor network.
//
//  Context assembly (document index retrieval) ALWAYS runs locally on all devices.
//  Inference routes to EdgeDaemon (preferred) or local CLaRa (8GB+ M-series fallback).
//

import Foundation
import DiverShared
import SwiftData

/// Protocol for interacting with the CLaRa Latent Search Engine.
public protocol AgenticSearching: Sendable {
    func ingestDocument(id: String, text: String, metadata: [String: String]) async throws -> Bool
    func performSearch(query: String, topK: Int) async throws -> AgenticSearchResult
}

/// Errors thrown by the Agentic Search Service.
public enum AgenticSearchError: Error {
    case edgeNodeUnavailable
    case edgeNodeMissingCapability
    case transportFailure(String)
}

/// The local service that bridges iOS searches to the macOS EdgeDaemon.
public final class AgenticSearchService: AgenticSearching, Sendable {
    
    private let router: PipelineEdgeRouter
    private let system: VisualIntelligenceActorSystem
    
    public init(router: PipelineEdgeRouter, system: VisualIntelligenceActorSystem) {
        self.router = router
        self.system = system
    }
    
    /// Ingests a document into the local CLaRa index (and optionally to EdgeDaemon).
    public func ingestDocument(id: String, text: String, metadata: [String: String] = [:]) async throws -> Bool {
        // Always ingest into the local document index (pure text, no ML needed)
        DiverLogger.search.info("📥 [AgenticSearch] Ingesting document \(id) into local index (\(text.count) chars)")
        let localChunks = CLaRaLatentService.shared.ingest(id: id, text: text, metadata: metadata)
        
        // Also try to ingest on EdgeDaemon if available
        let decision = await router.shouldOffload(task: .agenticSearch)
        if case .edge(let node, _) = decision {
            do {
                let identity = EdgeActorID(id: "AgenticSearch", nodeName: node.deviceName)
                let actor = try EdgeAgenticSearchActor.resolve(id: identity, using: system)
                let payload = AgenticSearchIngestPayload(
                    documentID: id,
                    textContent: text,
                    metadata: metadata
                )
                _ = try await actor.ingest(payload: payload)
            } catch {
                DiverLogger.search.warning("⚠️ [AgenticSearch] Edge ingestion failed (local index still updated): \(error)")
            }
        }
        
        return localChunks > 0
    }
    
    /// Queries CLaRa with context assembled from the local document index.
    ///
    /// Flow:
    /// 1. Assemble context from local sources (ALL devices — pure text, no ML)
    /// 2. Route inference to EdgeDaemon (sends context via `contextPayload`) or local CLaRa
    /// 3. Return answer with ProcessedItem IDs for deep-linking to ReferenceDetailView
    public func performSearch(query: String, topK: Int = 100) async throws -> AgenticSearchResult {
        DiverLogger.search.info("🔍 [AgenticSearch] Query: \(query)")
        
        // ── Step 1: Assemble context from local sources (ALL devices) ──
        let assembled = await assembleContext(for: query, topK: topK)
        
        DiverLogger.search.info("🔍 [AgenticSearch] Context: \(assembled.itemIDs.count) matched items, \(assembled.context.count) chars")
        
        // ── Step 2: Route inference to the best available target ──
        let decision = await router.shouldOffload(task: .agenticSearch)
        
        switch decision {
        case .edge(let node, _):
            DiverLogger.search.info("🔍 [AgenticSearch] Routing to EdgeDaemon: \(node.deviceName)")
            do {
                let identity = EdgeActorID(id: "AgenticSearch", nodeName: node.deviceName)
                let actor = try EdgeAgenticSearchActor.resolve(id: identity, using: system)
                
                // Send both the query AND our assembled context to the edge node
                let searchQuery = AgenticSearchQuery(
                    queryText: query,
                    topK: topK,
                    contextPayload: assembled.context
                )
                let result = try await actor.search(query: searchQuery)
                
                // Merge edge answer with our local item IDs for deep-linking
                return AgenticSearchResult(
                    generatedAnswer: result.generatedAnswer,
                    citedDocumentIDs: assembled.itemIDs
                )
            } catch {
                DiverLogger.search.warning("⚠️ [AgenticSearch] Edge transport failure: \(error). Trying local.")
                return try await runLocalInference(
                    query: query,
                    context: assembled.context,
                    itemIDs: assembled.itemIDs
                )
            }
            
        case .local:
            return try await runLocalInference(
                query: query,
                context: assembled.context,
                itemIDs: assembled.itemIDs
            )
        }
    }
    
    // MARK: - Context Assembly (runs on ALL devices — pure text, no ML)
    
    /// Assembled context result containing the text context and matching ProcessedItem IDs.
    private struct AssembledContext {
        let context: String
        let itemIDs: [String]  // ProcessedItem IDs for deep-linking to ReferenceDetailView
    }
    
    private func assembleContext(for query: String, topK: Int) async -> AssembledContext {
        var contextParts: [String] = []
        var matchedItemIDs: [String] = []
        
        // Source 1: CLaRa's in-memory document index (term-frequency retrieval)
        let claraResults = CLaRaLatentService.shared.retrieveContext(for: query, topK: topK)
        if !claraResults.isEmpty {
            let claraContext = claraResults.map { $0.text }.joined(separator: "\n---\n")
            contextParts.append("Library Matches (\(claraResults.count) items):\n\(claraContext)")
            // Extract unique ProcessedItem IDs, preserving relevance order (highest score first)
            var seen = Set<String>()
            for result in claraResults {
                if seen.insert(result.documentID).inserted {
                    matchedItemIDs.append(result.documentID)
                }
            }
        }
        
        // Source 2: Knowledge Graph retrieval
        if let kgService = await Services.shared.knowledgeGraphService {
            do {
                let results = try await kgService.retrieveRelevantContext(for: query, sessionID: nil)
                if !results.isEmpty {
                    let ragContext = results.map { $0.text }.joined(separator: "\n---\n")
                    contextParts.append("Knowledge Graph (\(results.count) matches):\n\(ragContext)")
                }
            } catch {
                DiverLogger.search.warning("⚠️ [AgenticSearch] KG retrieval failed: \(error)")
            }
        }
        
        // Source 3: Recent library items (supplemental context)
        // DiverDataStore is @MainActor — must access on main thread
        let libraryContext: String = await MainActor.run {
            guard let mc = Services.shared.modelContext else { return "" }
            let store = DiverDataStore(container: mc.container)
            return store.generateAgenticContextString(limit: 20)
        }
        if !libraryContext.isEmpty {
            contextParts.append("Recent Library Items:\n\(libraryContext)")
        }
        
        let fullContext = contextParts.isEmpty
            ? "No context available for query: \(query)"
            : contextParts.joined(separator: "\n\n")
        
        // Deduplicate item IDs (same item may match multiple chunks)
        let uniqueIDs = Array(NSOrderedSet(array: matchedItemIDs)) as? [String] ?? matchedItemIDs
        
        return AssembledContext(context: fullContext, itemIDs: uniqueIDs)
    }
    
    // MARK: - Local Inference (requires CLaRa model — 8GB+ M-series only)
    
    private func runLocalInference(query: String, context: String, itemIDs: [String]) async throws -> AgenticSearchResult {
        guard CLaRaLatentService.shared.isAvailable else {
            DiverLogger.search.warning("⚠️ [AgenticSearch] No inference target — returning retrieval results")
            // Return the matched items even though we can't run inference
            let fallbackAnswer = itemIDs.isEmpty
                ? "I couldn't find relevant information in your library for this query."
                : "I found \(itemIDs.count) relevant item(s) in your library. Tap the citations below to view them."
            return AgenticSearchResult(
                generatedAnswer: fallbackAnswer,
                citedDocumentIDs: itemIDs
            )
        }
        
        DiverLogger.search.info("🔍 [AgenticSearch] Running local CLaRa inference")
        
        do {
            try await CLaRaLatentService.shared.loadModel()
        } catch {
            DiverLogger.search.warning("⚠️ [AgenticSearch] CLaRa model load failed: \(error)")
            let fallbackAnswer = itemIDs.isEmpty
                ? "I couldn't load the model to answer your question."
                : "I found \(itemIDs.count) relevant item(s) in your library. Tap the citations below to view them."
            return AgenticSearchResult(
                generatedAnswer: fallbackAnswer,
                citedDocumentIDs: itemIDs
            )
        }
        
        let answer = try await CLaRaLatentService.shared.query(documentText: context, question: query)
        
        return AgenticSearchResult(
            generatedAnswer: answer ?? "Failed to generate answer.",
            citedDocumentIDs: itemIDs
        )
    }
}
