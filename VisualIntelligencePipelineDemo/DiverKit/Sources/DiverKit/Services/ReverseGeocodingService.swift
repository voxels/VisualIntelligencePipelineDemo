import Foundation
import CoreLocation
@preconcurrency import MapKit
import DiverShared

/// Priority-ranked reverse geocoding service.
/// Priority: MKLocalSearch (primary) → MKReverseGeocodingRequest (secondary) → Foursquare (tertiary)
@MainActor
public final class ReverseGeocodingService {
    
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
        
        // 2. Secondary: MKReverseGeocodingRequest for address fallback
        if let geocoderResult = await lookupWithReverseGeocoding(coordinate: coordinate) {
            print("📍 ReverseGeocoding: Found via MKReverseGeocodingRequest: \(geocoderResult.name ?? "Unknown")")
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
                let coordinate = item.location.coordinate
                return PlaceContext(
                    name: item.name ?? "Unknown",
                    categories: item.pointOfInterestCategory.map { [$0.rawValue] } ?? [],
                    placeID: nil, // MapKit doesn't provide stable IDs
                    address: formattedAddress(for: item),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    phoneNumber: item.phoneNumber,
                    website: item.url?.absoluteString
                )
            }
        } catch {
            print("⚠️ MKLocalSearch failed: \(error)")
        }
        
        return nil
    }
    
    // MARK: - MKReverseGeocodingRequest (Secondary)
    
    private func lookupWithReverseGeocoding(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        guard let request = MKReverseGeocodingRequest(location:CLLocation(latitude:coordinate.latitude, longitude: coordinate.longitude)) else { return nil }
        
        do {
            let mapItems = try await request.mapItems
            
            if let item = mapItems.first {
                let name = item.name ?? "Unknown"
                return PlaceContext(
                    name: name,
                    categories: [],
                    address: formattedAddress(for: item),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } catch {
            print("⚠️ MKReverseGeocodingRequest failed: \(error)")
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
    
    /// Builds a readable address from MKMapItem's address property (replaces deprecated placemark access).
    private func formattedAddress(for item: MKMapItem) -> String? {
        guard let address = item.address else { return nil }
        
        return address.shortAddress
    }
}
