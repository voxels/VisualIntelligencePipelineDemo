import SwiftUI
import DiverKit
import MapKit

public struct PlaceProfileView: View {
    let item: ProcessedItem
    @State private var showingPlaceDetails = false
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Interactive Map View
            if let coordinate = extractCoordinate(from: item) {
                let locationName = item.placeContext?.name ?? item.location ?? "Location"
                LocationMapView(coordinate: coordinate, locationName: locationName) {
                    // Action triggered on map tap
                }
                .frame(height: 250)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Foursquare / Detailed Place Context
            if let place = item.placeContext {
                PlaceContextView(context: place, baseLocation: item.location)
                    .onTapGesture {
                        showingPlaceDetails = true
                    }
                    .sheet(isPresented: $showingPlaceDetails) {
                        PlaceDetailSheet(context: place) { tag in
                            // Add tag to item
                            var updated = false
                            if !item.tags.contains(tag) {
                                item.tags.append(tag)
                                updated = true
                            }
                            if !item.categories.contains(tag) {
                                item.categories.append(tag)
                                updated = true
                            }
                            
                            if updated {
                                Task { @MainActor in try? item.modelContext?.save() }
                            }
                        }
                    }
                    .padding(.horizontal)
            }
        }
    }
    
    private func extractCoordinate(from item: ProcessedItem) -> CLLocationCoordinate2D? {
        if let place = item.placeContext, let lat = place.latitude, let lon = place.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let lat = item.latitude, let lon = item.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
}
