import Foundation
import CoreLocation
@preconcurrency import MapKit
import DiverShared

/// Priority-ranked reverse geocoding service.
/// Priority: MKLocalSearch (primary) → MKReverseGeocodingRequest (secondary) → Foursquare (tertiary)
public actor ReverseGeocodingService {
    
    /// Cache entry with TTL for reverse geocoding results
    private struct CachedGeocode: Sendable {
        let result: PlaceContext
        let timestamp: Date
        var isExpired: Bool { Date().timeIntervalSince(timestamp) > 3600 } // 1 hour TTL
    }
    
    /// Coordinate-keyed cache (4 decimal places ≈ 11m radius)
    private var geocodeCache: [String: CachedGeocode] = [:]
    
    /// Round coordinate to 4 decimal places for cache key
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 10000).rounded() / 10000
        let lon = (coordinate.longitude * 10000).rounded() / 10000
        return "\(lat),\(lon)"
    }
    
    public init() {
    }
    
    /// Lookup place information for a coordinate using priority-ranked services
    public func lookup(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        let key = cacheKey(for: coordinate)
        
        // Check cache first
        if let cached = geocodeCache[key], !cached.isExpired {
            DiverLogger.pipeline.debug("📍 ReverseGeocoding: Cache HIT for \(key)")
            return cached.result
        }
        
        // Cache miss — perform lookup
        let result = await performLookup(coordinate: coordinate)
        
        // Cache the result
        if let result {
            geocodeCache[key] = CachedGeocode(result: result, timestamp: Date())
        }
        
        return result
    }
    
    /// Perform the actual priority-ranked lookup (separated for caching)
    private func performLookup(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
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
    
    // MARK: - Helpers
    
    /// Builds a readable address from MKMapItem's address property (replaces deprecated placemark access).
    private func formattedAddress(for item: MKMapItem) -> String? {
        guard let address = item.address else { return nil }
        
        return address.shortAddress
    }
}
