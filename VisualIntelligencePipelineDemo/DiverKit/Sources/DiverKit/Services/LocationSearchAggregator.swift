import Foundation
import CoreLocation
import DiverShared

@MainActor
public struct LocationSearchAggregator {
    
    public static func fetchCandidates(
        query: String,
        center: CLLocationCoordinate2D,
        mapKitService: MapKitEnrichmentService?
    ) async -> [EnrichmentData] {
        
        // MapKit is now PRIMARY for search results
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
    
}

public struct SimpleMapFeature {
    public let coordinate: CLLocationCoordinate2D
    public let title: String?
    
    public init(coordinate: CLLocationCoordinate2D, title: String?) {
        self.coordinate = coordinate
        self.title = title
    }
}

