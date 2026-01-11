import Foundation

/// A service protocol for retrieving relevant context from the knowledge graph (KnowMaps).
public protocol KnowledgeGraphRetrievalService: Sendable {
    /// Retrieves relevant items or concepts based on a query string (e.g., visual labels).
    /// - Parameter query: The text query to search for (e.g., "coffee", "book").
    /// - Returns: A list of relevant strings (titles, categories, or purposes) with their associated weights.
    @MainActor
    func retrieveRelevantContext(for query: String) async throws -> [(text: String, weight: Double)]
}
