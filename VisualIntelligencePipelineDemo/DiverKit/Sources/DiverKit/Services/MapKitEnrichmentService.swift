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
                    placeID: nil, // MapKit doesn't expose stable Place IDs easily in this flow
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
        // Use MKLocalPointsOfInterestRequest if available, or MKLocalSearch
        let request = MKLocalPointsOfInterestRequest(center: location, radius: 500) // 500m radius
        
        do {
            let response = try await MKLocalSearch(request: request).start()
            
            return response.mapItems.prefix(limit).map { item in
                mapItemToEnrichmentData(item)
            }
        } catch {
            // Fallback to generic search if POI request fails or returns nothing useful?
            // Actually MKLocalPointsOfInterestRequest is fairly robust for "nearby".
            return []
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
    
    // MARK: - Helper
    
    private func mapItemToEnrichmentData(_ item: MKMapItem) -> EnrichmentData {
        let name = item.name ?? "Unknown Place"
        let category = item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Place"
        
        let placeContext = PlaceContext(
            name: name,
            categories: [category],
            placeID: nil, // MapKit Items are transient usually
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
