//
//  AgenticSearchService.swift
//  DiverKit
//
//  Client-side wrapper that uses the PipelineEdgeRouter to discover an EdgeDaemon
//  and send CLaRa Agentic Search payloads/queries over the Distributed Actor network.
//

import Foundation
import DiverShared

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
public final class AgenticSearchService: AgenticSearching, @unchecked Sendable {
    
    private let router: PipelineEdgeRouter
    private let system: VisualIntelligenceActorSystem
    
    public init(router: PipelineEdgeRouter, system: VisualIntelligenceActorSystem) {
        self.router = router
        self.system = system
    }
    
    /// Sends a newly captured document/photo to the EdgeDaemon to be compressed into a latent vector.
    public func ingestDocument(id: String, text: String, metadata: [String: String] = [:]) async throws -> Bool {
        let decision = await router.shouldOffload(task: .agenticSearch)
        
        switch decision {
        case .edge(let node, _):
            // We have a connected Mac. Resolve the Distributed Actor and send the payload.
            do {
                let identity = EdgeActorID(id: "AgenticSearch", nodeName: node.deviceName)
                let actor = try EdgeAgenticSearchActor.resolve(id: identity, using: system)
                
                let payload = AgenticSearchIngestPayload(
                    documentID: id,
                    textContent: text,
                    metadata: metadata
                )
                
                return try await actor.ingest(payload: payload)
            } catch {
                throw AgenticSearchError.transportFailure(error.localizedDescription)
            }
            
        case .local:
            // CLaRa-7B is too large to run natively on the iPhone.
            // If the Mac is unreachable, we cannot ingest the latent.
            throw AgenticSearchError.edgeNodeUnavailable
        }
    }
    
    /// Queries the EdgeDaemon's CLaRa engine with a natural language search.
    public func performSearch(query: String, topK: Int = 5) async throws -> AgenticSearchResult {
        let decision = await router.shouldOffload(task: .agenticSearch)
        
        switch decision {
        case .edge(let node, _):
            do {
                let identity = EdgeActorID(id: "AgenticSearch", nodeName: node.deviceName)
                let actor = try EdgeAgenticSearchActor.resolve(id: identity, using: system)
                
                let searchQuery = AgenticSearchQuery(queryText: query, topK: topK)
                return try await actor.search(query: searchQuery)
            } catch {
                throw AgenticSearchError.transportFailure(error.localizedDescription)
            }
            
        case .local:
            throw AgenticSearchError.edgeNodeUnavailable
        }
    }
}
