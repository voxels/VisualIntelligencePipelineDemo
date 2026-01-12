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
    
    public func fetchDetails(for fsqID: String) async throws -> EnrichmentData? {
        guard let apiKey = apiKey else { return nil }
        
        let urlString = "https://api.foursquare.com/v3/places/\(fsqID)"
        var components = URLComponents(string: urlString)
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "fsq_id,name,categories,location,geocodes,price,rating,tel,website,photos,tips")
        ]
        
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        let decoder = JSONDecoder()
        let place = try decoder.decode(FoursquarePlace.self, from: data)
        return convertToEnrichmentData(place)
    }

    public func searchNearby(location: CLLocationCoordinate2D, limit: Int = 5) async throws -> [EnrichmentData] {
        guard let apiKey = apiKey else { return [] }
        
        var components = URLComponents(string: "https://api.foursquare.com/v3/places/search")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "DISTANCE"),
            URLQueryItem(name: "fields", value: "fsq_id,name,categories,location,geocodes,price,rating,tel,website,photos,tips")
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
            if let enriched = convertToEnrichmentData(place) {
                enrichedResults.append(enriched)
            }
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
            URLQueryItem(name: "sort", value: "DISTANCE"),
            URLQueryItem(name: "fields", value: "fsq_id,name,categories,location,geocodes,price,rating,tel,website,photos,tips")
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
            return convertToEnrichmentData(place)
        }
    }
    
    public func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        // We could implement Foursquare search by query here as well
        // For now, focusing on location-based venue search
        return nil
    }

    private func convertToEnrichmentData(_ place: FoursquarePlace) -> EnrichmentData? {
        let cats = place.categories.map { $0.name }
        
        // Photos
        let photoUrls = place.photos?.compactMap { $0.prefix + "original" + $0.suffix }
        
        // Tips
        let tips = place.tips?.map { $0.text }
        
        // Price Level
        var priceLevel: String?
        if let p = place.price {
            priceLevel = String(repeating: "$", count: p)
        }
        
        // Create PlaceContext
        let placeContext = PlaceContext(
            name: place.name,
            categories: cats,
            placeID: place.fsq_id,
            address: place.location.address,
            rating: place.rating,
            latitude: place.geocodes?.main?.latitude,
            longitude: place.geocodes?.main?.longitude,
            priceLevel: priceLevel,
            phoneNumber: place.tel,
            website: place.website,
            photos: photoUrls,
            tips: tips
        )
        
        return EnrichmentData(
            title: place.name,
            descriptionText: nil,
            categories: cats,
            styleTags: [],
            location: place.location.address,
            price: place.price.map { Double($0) },
            rating: place.rating,
            questions: [],
            placeContext: placeContext
        )
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
    let price: Int?
    let rating: Double?
    let tel: String?
    let website: String?
    let photos: [FoursquarePhoto]?
    let tips: [FoursquareTip]?
}

private struct FoursquareGeocodes: Codable {
    let main: FoursquareCoordinates?
}

private struct FoursquareCoordinates: Codable {
    let latitude: Double
    let longitude: Double
}

private struct FoursquareCategory: Codable {
    let id: String
    let name: String
}

private struct FoursquareLocation: Codable {
    let address: String?
    let country: String?
}

private struct FoursquarePhoto: Codable {
    let prefix: String
    let suffix: String
}

private struct FoursquareTip: Codable {
    let text: String
}
