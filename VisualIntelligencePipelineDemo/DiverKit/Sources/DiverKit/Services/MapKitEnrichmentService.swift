import Foundation
import CoreLocation
import MapKit
import DiverShared

/// Enrichment service using Apple's MapKit (MKLocalSearch)
public final class MapKitEnrichmentService: ContextualEnrichmentService, @unchecked Sendable {
    
    public init() {}
    
    public func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        // Use CLGeocoder for reverse geocoding to get basic place info
        let geocoder = CLGeocoder()
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(clLocation) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let placeContext = PlaceContext(
                    name: placemark.name ?? "Unknown Location",
                    categories: [placemark.category].compactMap { $0 }, // Helper extension below? Or just general category
                    placeID: "mk-reverse-\(location.latitude)-\(location.longitude)",
                    address: [placemark.thoroughfare, placemark.locality].compactMap { $0 }.joined(separator: ", "),
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                
                let data = EnrichmentData(
                    title: placemark.name,
                    descriptionText: placemark.formattedTitle, // e.g. Address
                    categories: [placemark.category].compactMap { $0 },
                    location: placemark.formattedTitle,
                    placeContext: placeContext
                )
                continuation.resume(returning: data)
            }
        }
    }
    
    public func searchNearby(location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        // 1. Try POI Request (Radius 2000m)
        let request = MKLocalPointsOfInterestRequest(center: location, radius: 2000)
        
        do {
            let response = try await MKLocalSearch(request: request).start()
            let items = response.mapItems
            
            if !items.isEmpty {
                return items.prefix(limit).map { mapItemToEnrichmentData($0) }
            }
            
            // 2. Fallback to Generic Search if POI empty
            // Sometimes POI request is strict. Use generic "Point of Interest" query.
            return try await search(query: "Point of Interest", location: location, limit: limit)
            
        } catch {
            // Fallback to Generic Search on error
            return try await search(query: "Point of Interest", location: location, limit: limit)
        }
    }
    
    public func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: location, latitudinalMeters: 5000, longitudinalMeters: 5000)
        
        let response = try await MKLocalSearch(request: request).start()
        
        return response.mapItems.prefix(limit).map { item in
            mapItemToEnrichmentData(item)
        }
    }
    
    public func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        guard let location = location else { return nil }
        let results = try await search(query: query, location: location, limit: 1)
        return results.first
    }
    
    public func fetchDetails(for id: String) async throws -> EnrichmentData? {
        // MapKit doesn't support persistent ID lookup in a simple way for this flow
        return nil
    }
    
    // MARK: - Helper
    
    private func mapItemToEnrichmentData(_ item: MKMapItem) -> EnrichmentData {
        let name = item.name ?? "Unknown Place"
        let category = item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Place"
        
        let placeContext = PlaceContext(
            name: name,
            categories: [category],
            placeID: "mk-\(name.hash)-\(item.placemark.coordinate.latitude)-\(item.placemark.coordinate.longitude)", // Deterministic ID for UI stability
            address: item.placemark.formattedTitle,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            phoneNumber: item.phoneNumber,
            website: item.url?.absoluteString
        )
        
        return EnrichmentData(
            title: name,
            descriptionText: item.placemark.formattedTitle,
            categories: [category],
            location: item.placemark.formattedTitle,
            placeContext: placeContext
        )
    }
}

private extension CLPlacemark {
    var category: String? {
        if #available(iOS 13.0, *) {
            // Very rough approximation if needed, but CLPlacemark doesn't have a direct 'category' like POI
            if let _ = self.areasOfInterest { return "Point of Interest" }
        }
        return nil
    }
    
    var formattedTitle: String? {
        // Construct a readable address
        let components = [thoroughfare, subThoroughfare, locality, administrativeArea].compactMap { $0 }
        return components.joined(separator: ", ")
    }
}
