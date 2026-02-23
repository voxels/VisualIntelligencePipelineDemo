import SwiftUI
import DiverKit
import MapKit

// MARK: - Local Location Map View
public struct LocationMapView: View {
    @State private var position: MapCameraPosition
    let locationName: String?
    let coordinate: CLLocationCoordinate2D?
    let onOpenPlaces: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    public init(coordinate: CLLocationCoordinate2D?, locationName: String?, onOpenPlaces: @escaping () -> Void) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.onOpenPlaces = onOpenPlaces
        
        if let coordinate = coordinate {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))))
        } else {
            self._position = State(initialValue: .automatic)
        }
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if let coordinate = coordinate {
                    Marker(locationName ?? "Location", coordinate: coordinate)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            
            // Floating Card for Place Details
            HStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(locationName ?? "Unknown Location")
                            .font(.headline)
                        if let coordinate {
                            Text("\(coordinate.latitude), \(coordinate.longitude)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: onOpenPlaces) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(16)
                .shadow(radius: 5)
            }
            .padding()
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
