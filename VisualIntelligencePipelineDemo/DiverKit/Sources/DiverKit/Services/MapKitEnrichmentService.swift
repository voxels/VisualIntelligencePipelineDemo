import Foundation
import CoreLocation
import MapKit
import DiverShared

/// Enrichment service using Apple's MapKit (MKLocalSearch)
/// Safety: @unchecked Sendable is correct — no mutable stored properties,
public final class MapKitEnrichmentService: ContextualEnrichmentService, Sendable {

    public init() {}
    
    public func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        // Use MKReverseGeocodingRequest (replaces deprecated CLGeocoder)
        guard let request = MKReverseGeocodingRequest(location:CLLocation(latitude: location.latitude, longitude: location.longitude)) else { return nil }
        let mapItems = try await request.mapItems
        guard let item = mapItems.first else { return nil }
        
        let name = item.name ?? "Unknown Location"
        let addressString = formattedAddress(for: item)
        let category = item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Place"

        let placeContext = PlaceContext(
            name: name,
            categories: [category],
            placeID: "mk-reverse-\(location.latitude)-\(location.longitude)",
            address: addressString ?? "",
            latitude: location.latitude,
            longitude: location.longitude
        )

        let data = EnrichmentData(
            title: name,
            descriptionText: addressString,
            categories: [category],
            location: addressString,
            placeContext: placeContext
        )
        return data
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
        // MapKit doesn't support persistent ID lookup natively.
        // However, we encode identifying info in our ID format: "mk-[nameHash]-[lat]-[lon]" or "mk-reverse-[lat]-[lon]"
        
        guard id.starts(with: "mk-") else { return nil }
        
        let components = id.split(separator: "-")
        
        // Extract Coordinates from ID suffix
        // Format assumption: ...-lat-lon
        guard components.count >= 3,
              let lat = Double(components[components.count - 2]),
              let lon = Double(components[components.count - 1]) else {
            return nil
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let location = CLLocation(latitude: lat, longitude: lon)
        
        // 1. Check Contact Locations (Home/Work) - "Unless it's a contact location"
        if let contactService = await Services.shared.contactService {
            if let home = try? await contactService.getHomeLocation(), home.distance(from: location) < 300 {
                return nil // Treat as handled by ContactService/Personal Context
            }
            if let work = try? await contactService.getWorkLocation(), work.distance(from: location) < 300 {
                return nil // Treat as handled by ContactService
            }
        }
        
        // 2. Return the MapKit result
        return try await enrich(location: coordinate)
    }
    
    // MARK: - Helper
    
    private func mapItemToEnrichmentData(_ item: MKMapItem) -> EnrichmentData {
        let name = item.name ?? "Unknown Place"
        let category = item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Place"
        let coordinate = item.location.coordinate
        let addressString = formattedAddress(for: item)
        
        let placeContext = PlaceContext(
            name: name,
            categories: [category],
            placeID: "mk-\(name.hash)-\(coordinate.latitude)-\(coordinate.longitude)", // Deterministic ID for UI stability
            address: addressString,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            phoneNumber: item.phoneNumber,
            website: item.url?.absoluteString
        )
        
        return EnrichmentData(
            title: name,
            descriptionText: addressString,
            categories: [category],
            location: addressString,
            placeContext: placeContext
        )
    }
    
    /// Builds a readable address string from MKMapItem's address property (replaces deprecated placemark access).
    private func formattedAddress(for item: MKMapItem) -> String? {
        guard let address = item.address else { return nil }
        return address.shortAddress
    }
}

