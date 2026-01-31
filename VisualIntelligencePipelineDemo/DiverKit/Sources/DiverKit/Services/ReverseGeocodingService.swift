import Foundation
import CoreLocation
import MapKit
import DiverShared

/// Priority-ranked reverse geocoding service.
/// Priority: MKLocalSearch (primary) → CLGeocoder (secondary) → Foursquare (tertiary)
@MainActor
public final class ReverseGeocodingService {
    
    private let geocoder = CLGeocoder()
    private var foursquareService: ContextualEnrichmentService?
    
    public init(foursquareService: ContextualEnrichmentService? = nil) {
        self.foursquareService = foursquareService
    }
    
    /// Lookup place information for a coordinate using priority-ranked services
    public func lookup(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        // 1. Primary: MKLocalSearch for MapKit place data
        if let mapKitResult = await lookupWithMapKit(coordinate: coordinate) {
            print("📍 ReverseGeocoding: Found via MKLocalSearch: \(mapKitResult.name ?? "Unknown")")
            return mapKitResult
        }
        
        // 2. Secondary: CLGeocoder for address fallback
        if let geocoderResult = await lookupWithGeocoder(coordinate: coordinate) {
            print("📍 ReverseGeocoding: Found via CLGeocoder: \(geocoderResult.name ?? "Unknown")")
            return geocoderResult
        }
        
        // 3. Tertiary: Foursquare for POI data
        if let foursquareResult = await lookupWithFoursquare(coordinate: coordinate) {
            print("📍 ReverseGeocoding: Found via Foursquare: \(foursquareResult.name ?? "Unknown")")
            return foursquareResult
        }
        
        print("⚠️ ReverseGeocoding: No results for coordinate \(coordinate)")
        return nil
    }
    
    // MARK: - MKLocalSearch (Primary)
    
    private func lookupWithMapKit(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "point of interest"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 100,
            longitudinalMeters: 100
        )
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            
            if let item = response.mapItems.first {
                return PlaceContext(
                    name: item.name ?? item.placemark.title ?? "Unknown",
                    categories: item.pointOfInterestCategory.map { [$0.rawValue] } ?? [],
                    placeID: nil, // MapKit doesn't provide stable IDs
                    address: formatAddress(item.placemark),
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    phoneNumber: item.phoneNumber,
                    website: item.url?.absoluteString
                )
            }
        } catch {
            print("⚠️ MKLocalSearch failed: \(error)")
        }
        
        return nil
    }
    
    // MARK: - CLGeocoder (Secondary)
    
    private func lookupWithGeocoder(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                let name = placemark.name ?? placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                return PlaceContext(
                    name: name,
                    categories: [],
                    address: formatAddress(placemark),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } catch {
            print("⚠️ CLGeocoder failed: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Foursquare (Tertiary)
    
    private func lookupWithFoursquare(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        guard let foursquare = foursquareService else { return nil }
        
        do {
            let enrichments = try await foursquare.searchNearby(
                location: coordinate,
                limit: 1
            )
            
            if let first = enrichments.first, let placeContext = first.placeContext {
                return placeContext
            }
        } catch {
            print("⚠️ Foursquare lookup failed: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func formatAddress(_ placemark: MKPlacemark) -> String? {
        var components: [String] = []
        if let thoroughfare = placemark.thoroughfare { components.append(thoroughfare) }
        if let locality = placemark.locality { components.append(locality) }
        if let administrativeArea = placemark.administrativeArea { components.append(administrativeArea) }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
    
    private func formatAddress(_ placemark: CLPlacemark) -> String? {
        var components: [String] = []
        if let thoroughfare = placemark.thoroughfare { components.append(thoroughfare) }
        if let locality = placemark.locality { components.append(locality) }
        if let administrativeArea = placemark.administrativeArea { components.append(administrativeArea) }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}
