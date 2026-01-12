import Foundation
import CoreLocation
import DiverShared

/// Enrichment service using DuckDuckGo Instant Answer API
/// API: https://api.duckduckgo.com/?q=...&format=json
public final class DuckDuckGoEnrichmentService: ContextualEnrichmentService, LinkEnrichmentService, @unchecked Sendable {
    
    public init() {}
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        // Use the URL string as the query for DuckDuckGo
        return try await enrich(query: url.absoluteString, location: nil)
    }
    
    public func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        // DuckDuckGo is query-based, not coordinate-based. Use query method instead.
        return nil
    }
    
    public func searchNearby(location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        return [] // not supported
    }
    
    public func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        // Simple shim using existing enrich
        if let data = try await enrich(query: query, location: location) {
            return [data]
        }
        return []
    }
    
    public func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&t=DiverApp&no_redirect=1&no_html=1") else {
            return nil
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DiverLogger.pipeline.error("DuckDuckGo API request failed")
            return nil
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(DuckDuckGoResponse.self, from: data)
        
        // Prioritize AbstractText (main summary) or Abstract (sometimes contains HTML but we asked for no_html)
        // If empty, check RelatedTopics
        
        var description = result.AbstractText
        if description.isEmpty {
            description = result.Heading
        }
        
        // If still empty, try to grab the first related topic
        if description.isEmpty, let firstTopic = result.RelatedTopics.first {
            description = firstTopic.Text ?? ""
        }
        
        // If we found nothing useful, return nil
        if description.isEmpty {
            return nil
        }
        
        let title = result.Heading.isEmpty ? query : result.Heading
        
        // DuckDuckGo doesn't give structured categories usually, but sometimes "Entity"
        let categories: [String] = [] 
        
        // Generate questions as usual
        let initialData = EnrichmentData(
            title: title,
            descriptionText: description,
            categories: categories,
            location: nil, // DDG doesn't give location
            questions: [],
            webContext: WebContext(
                siteName: "DuckDuckGo: \(title)",
                faviconURL: result.Image.isEmpty ? nil : result.Image
            )
        )
        // Note: We use the AbstractURL if available as the link
        var finalWebContext: WebContext?
        if !result.AbstractURL.isEmpty {
             finalWebContext = WebContext(
                siteName: "DuckDuckGo: \(title)",
                faviconURL: result.Image.isEmpty ? nil : result.Image,
                isReaderAvailable: true
            )
        }
        
        let contextService = ContextQuestionService()
        let (_, generatedQuestions, _, tags) = try await contextService.processContext(from: initialData)
        
        return EnrichmentData(
            title: title,
            descriptionText: description,
            categories: tags,
            questions: generatedQuestions,
            webContext: finalWebContext
        )
    }
    
    public func fetchDetails(for id: String) async throws -> EnrichmentData? {
        // ID-based lookup not supported by DuckDuckGo Instant Answer API
        return nil
    }
}

// MARK: - API Models

private struct DuckDuckGoResponse: Codable {
    let Abstract: String
    let AbstractText: String
    let Heading: String
    let Image: String
    let AbstractURL: String
    let RelatedTopics: [DDGRelatedTopic]
}

private struct DDGRelatedTopic: Codable {
    let Result: String?
    let Text: String?
    // Nested topics might exist but keeping it simple
}
