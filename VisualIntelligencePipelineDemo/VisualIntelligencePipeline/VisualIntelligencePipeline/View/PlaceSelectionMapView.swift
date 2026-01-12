import SwiftUI
import MapKit
import DiverKit
import DiverShared

struct PlaceSelectionMapView: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedDetail: EnrichmentData?
    @State private var isLoading = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            MapReader { reader in
                Map(position: $position, selection: Binding(
                    get: { nil },
                    set: { feature in
                        if let feature = feature as? MapFeature {
                            Task {
                                await resolveMapFeature(feature)
                            }
                        }
                    }
                )) {
                    // Candidates
                    ForEach(viewModel.placeCandidates, id: \.placeContext?.placeID) { candidate in
                        if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                            Annotation(candidate.title ?? "Place", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                Button {
                                    viewModel.selectPlace(candidate)
                                    dismiss()
                                } label: {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                            }
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                    MapPitchToggle()
                }
                .onMapCameraChange { context in
                    visibleRegion = context.region
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack {
                         Button {
                            Task {
                                await searchHere()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Search Here")
                            }
                            .padding()
                            .background(.thickMaterial)
                            .cornerRadius(8)
                            .shadow(radius: 2)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
            .onSubmit(of: .search) {
                Task {
                    await searchHere()
                }
            }
            .task {
                // Initial load
                if viewModel.placeCandidates.isEmpty {
                    await searchHere()
                }
            }
            .onAppear {
                setupInitialPosition()
            }
        }
    }
    
    private func setupInitialPosition() {
        if let coordinate = viewModel.currentCaptureCoordinate {
            position = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        } else {
             Task {
                 if let current = await Services.shared.locationService?.getCurrentLocation() {
                      await MainActor.run {
                          withAnimation {
                              position = .region(MKCoordinateRegion(center: current.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                          }
                      }
                 } else {
                     await MainActor.run {
                         position = .region(MKCoordinateRegion(
                             center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                             span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                         ))
                     }
                 }
             }
        }
    }
    
    private func resolveMapFeature(_ feature: MapFeature) async {
        let simpleFeature = SimpleMapFeature(coordinate: feature.coordinate, title: feature.title)

        if let data = await LocationSearchAggregator.resolveMapFeature(
            feature: simpleFeature,
            foursquareService: Services.shared.foursquareService,
            mapKitService: Services.shared.mapKitService
        ) {
             await MainActor.run {
                viewModel.selectPlace(data)
                dismiss()
            }
        }
    }
    
    private func searchHere() async {
        isLoading = true
        defer { isLoading = false }
        
        let center = visibleRegion?.center ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        
        let results = await LocationSearchAggregator.fetchCandidates(
            query: searchText,
            center: center,
            foursquareService: Services.shared.foursquareService,
            mapKitService: Services.shared.mapKitService
        )
        
        await MainActor.run {
            viewModel.placeCandidates = results
        }
    }
}
