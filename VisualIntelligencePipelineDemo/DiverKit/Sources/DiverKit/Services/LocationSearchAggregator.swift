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
        
        async let fsqTask: [EnrichmentData] = {
            if let service = foursquareService {
                do {
                    return query.isEmpty ? try await service.searchNearby(location: center, limit: 30) : try await service.search(query: query, location: center, limit: 30)
                } catch {
                    print("Foursquare search failed: \(error)")
                }
            }
            return []
        }()
        
        async let mapKitTask: [EnrichmentData] = {
            if let service = mapKitService {
                do {
                    return query.isEmpty ? try await service.searchNearby(location: center, limit: 30) : try await service.search(query: query, location: center, limit: 30)
                } catch {
                    print("MapKit search failed: \(error)")
                }
            }
            return []
        }()
        
        let (fsqResults, mapResults) = await (fsqTask, mapKitTask)
        
        // Merge and Deduplicate
        var merged: [EnrichmentData] = []
        var seenNames = Set<String>()
        
        func addIfUnique(_ items: [EnrichmentData]) {
            for item in items {
                let name = item.title?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
                if name.isEmpty { continue }
                
                if seenNames.contains(name) { continue }
                
                seenNames.insert(name)
                merged.append(item)
            }
        }
        
        // Prioritize MapKit for local landmarks, but Foursquare has better venue details
        // Interleaving or appending? Existing logic prioritized MapKit then Foursquare.
        // Let's stick to valid results.
        
        // Add MapKit results
        addIfUnique(mapResults)
        
        // Add Foursquare results
        addIfUnique(fsqResults)
        
        return merged
    }
    
    public static func resolveMapFeature(
        feature: SimpleMapFeature,
        foursquareService: ContextualEnrichmentService?,
        mapKitService: MapKitEnrichmentService?
    ) async -> EnrichmentData? {
        let coordinate = feature.coordinate
        let title = feature.title ?? "Selected Location"
        
        // 1. Try Foursquare Lookup by Name/Location
        if let fsqService = foursquareService {
            do {
                let results = try await fsqService.search(query: title, location: coordinate, limit: 1)
                if let bestMatch = results.first {
                    return bestMatch
                }
            } catch {
                print("Foursquare lookup failed during resolve: \(error)")
            }
        }
        
        // 2. Fallback to MapKit
        if let mapService = mapKitService {
             if let placeData = try? await mapService.enrich(query: title, location: coordinate) {
                 return placeData
             }
        }
        
        // 3. Manual Construction
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
