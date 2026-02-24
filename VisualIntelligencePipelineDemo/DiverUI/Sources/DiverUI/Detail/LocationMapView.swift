//
//  LocationMapView.swift
//  DiverUI — cross-platform
//
//  UIColor.systemBackground replaced with .background material.
//  navigationBarTitleDisplayMode guarded under #if os(iOS).
//

import SwiftUI
import DiverKit
import MapKit

public struct LocationMapView: View {
    @State private var position: MapCameraPosition
    public let locationName: String?
    public let coordinate: CLLocationCoordinate2D?
    public let onOpenPlaces: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(coordinate: CLLocationCoordinate2D?, locationName: String?, onOpenPlaces: @escaping () -> Void) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.onOpenPlaces = onOpenPlaces
        if let c = coordinate {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if let coord = coordinate {
                    Marker(locationName ?? "Location", coordinate: coord)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }

            HStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(locationName ?? "Unknown Location").font(.headline)
                        if let coord = coordinate {
                            Text("\(coord.latitude, specifier: "%.4f"), \(coord.longitude, specifier: "%.4f")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: onOpenPlaces) {
                        Image(systemName: "map.fill").font(.title2)
                            .padding(12).background(Color.blue).foregroundColor(.white).clipShape(Circle())
                    }
                }
                .padding().background(.background).clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 5)
            }
            .padding()
        }
        .navigationTitle("Location")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
