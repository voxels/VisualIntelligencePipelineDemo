import Foundation

/// A service protocol for retrieving relevant context from the knowledge graph (KnowMaps).
public protocol KnowledgeGraphRetrievalService: Sendable {
    /// Retrieves relevant items or concepts based on a query string (e.g., visual labels).
    /// - Parameters:
    ///   - query: The text query to search for (e.g., "coffee", "book").
    ///   - sessionID: Optional session ID to scope the context retrieval. When provided, only retrieves context from items in that session.
    /// - Returns: A list of relevant strings (titles, categories, or purposes) with their associated weights.
    @MainActor
    func retrieveRelevantContext(for query: String, sessionID: String?) async throws -> [(text: String, weight: Double)]
}
