import Foundation
import CoreLocation
import DiverShared

@MainActor
public struct LocationSearchAggregator {
    
    public static func fetchCandidates(
        query: String,
        center: CLLocationCoordinate2D,
        foursquareService: ContextualEnrichmentService?,
        mapKitService: MapKitEnrichmentService?
    ) async -> [EnrichmentData] {
        
        // MapKit is now PRIMARY for search results
        // Foursquare is used for supplemental enrichment ONLY (in detail view)
        var mapResults: [EnrichmentData] = []
        
        if let service = mapKitService {
            do {
                mapResults = query.isEmpty 
                    ? try await service.searchNearby(location: center, limit: 30) 
                    : try await service.search(query: query, location: center, limit: 30)
            } catch {
                print("MapKit search failed: \(error)")
            }
        }
        
        // Deduplicate by name (in case of multiple MapKit sources)
        var seen = Set<String>()
        return mapResults.filter { item in
            let name = item.title?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
            if name.isEmpty || seen.contains(name) { return false }
            seen.insert(name)
            return true
        }
    }
    
    public static func resolveMapFeature(
        feature: SimpleMapFeature,
        foursquareService: ContextualEnrichmentService?,
        mapKitService: MapKitEnrichmentService?
    ) async -> EnrichmentData? {
        let coordinate = feature.coordinate
        let title = feature.title ?? "Selected Location"
        
        // 1. Try MapKit first (primary source)
        if let mapService = mapKitService {
            if let placeData = try? await mapService.enrich(query: title, location: coordinate) {
                return placeData
            }
        }
        
        // 2. Manual Construction fallback
        return EnrichmentData(
            title: title,
            descriptionText: "Apple Maps Location",
            categories: ["Point of Interest"],
            location: title,
            placeContext: PlaceContext(
                name: title,
                categories: ["POI"],
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
    }
    
    /// Fetches supplemental Foursquare data for a place (categories, ratings, tips, photos).
    /// Use this in detail views to enrich MapKit results with Foursquare data.
    /// - Parameters:
    ///   - title: The place name to search for
    ///   - coordinate: The location coordinate
    ///   - foursquareService: The Foursquare service
    /// - Returns: Enriched PlaceContext with Foursquare data, or nil if not found
    public static func fetchFoursquareSupplementalData(
        title: String,
        coordinate: CLLocationCoordinate2D,
        foursquareService: ContextualEnrichmentService?
    ) async -> PlaceContext? {
        guard let fsqService = foursquareService else { return nil }
        
        do {
            let results = try await fsqService.search(query: title, location: coordinate, limit: 1)
            if let bestMatch = results.first {
                return bestMatch.placeContext
            }
        } catch {
            print("Foursquare supplemental lookup failed: \(error)")
        }
        return nil
    }
}

public struct SimpleMapFeature {
    public let coordinate: CLLocationCoordinate2D
    public let title: String?
    
    public init(coordinate: CLLocationCoordinate2D, title: String?) {
        self.coordinate = coordinate
        self.title = title
    }
}

