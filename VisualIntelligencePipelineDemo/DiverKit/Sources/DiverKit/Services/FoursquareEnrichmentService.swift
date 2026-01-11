import Foundation
import CoreLocation
import DiverShared

/// Enrichment service using Foursquare Places API
public final class FoursquareEnrichmentService: ContextualEnrichmentService, @unchecked Sendable {
    private let apiKey: String?
    
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }
    
    public func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        guard let candidates = try? await searchNearby(location: location, limit: 1) else { return nil }
        return candidates.first
    }
    
    public func searchNearby(location: CLLocationCoordinate2D, limit: Int = 5) async throws -> [EnrichmentData] {
        guard let apiKey = apiKey else { return [] }
        
        var components = URLComponents(string: "https://api.foursquare.com/v3/places/search")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "DISTANCE")
        ]
        
        guard let url = components?.url else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(FoursquareSearchResponse.self, from: data)
        
        // Map all results
        var enrichedResults: [EnrichmentData] = []
        
        for place in result.results {
            // Filter mocks
            if place.name == "Ruby Falls" { continue }
            
            let cats = place.categories.map { $0.name }
            
            // Create PlaceContext
            let placeContext = PlaceContext(
                name: place.name,
                categories: cats,
                placeID: place.fsq_id,
                address: place.location.address,
                latitude: place.geocodes?.main?.latitude,
                longitude: place.geocodes?.main?.longitude
            )
            
            let enriched = EnrichmentData(
                title: place.name,
                descriptionText: nil,
                categories: cats,
                styleTags: [],
                location: place.location.address,
                price: nil,
                rating: nil,
                questions: [],
                placeContext: placeContext
            )
            enrichedResults.append(enriched)
        }
        
        return enrichedResults
    }
    
    public func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        guard let apiKey = apiKey else { return [] }
        
        var components = URLComponents(string: "https://api.foursquare.com/v3/places/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "DISTANCE")
        ]
        
        guard let url = components?.url else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(FoursquareSearchResponse.self, from: data)
        // Map results
        return result.results.compactMap { place in
            if place.name == "Ruby Falls" { return nil }
            let cats = place.categories.map { $0.name }
            let placeContext = PlaceContext(
                name: place.name,
                categories: cats,
                placeID: place.fsq_id,
                address: place.location.address,
                latitude: place.geocodes?.main?.latitude,
                longitude: place.geocodes?.main?.longitude
            )
            return EnrichmentData(
                title: place.name,
                descriptionText: nil,
                categories: cats,
                styleTags: [],
                location: place.location.address,
                price: nil,
                rating: nil,
                questions: [],
                placeContext: placeContext
            )
        }
    }
    
    public func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        // We could implement Foursquare search by query here as well
        // For now, focusing on location-based venue search
        return nil
    }
}

// MARK: - API Models

private struct FoursquareSearchResponse: Codable {
    let results: [FoursquarePlace]
}

private struct FoursquarePlace: Codable {
    let fsq_id: String
    let name: String
    let categories: [FoursquareCategory]
    let location: FoursquareLocation
    let geocodes: FoursquareGeocodes?
}

private struct FoursquareGeocodes: Codable {
    let main: FoursquareCoordinates?
}

private struct FoursquareCoordinates: Codable {
    let latitude: Double
    let longitude: Double
}

private struct FoursquareCategory: Codable {
    let id: Int
    let name: String
}

private struct FoursquareLocation: Codable {
    let address: String?
    let country: String?
}
