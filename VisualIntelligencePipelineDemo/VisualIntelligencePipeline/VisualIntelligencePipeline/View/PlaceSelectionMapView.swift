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
        }
    }
    
    private func resolveMapFeature(_ feature: MapFeature) async {
        let coordinate = feature.coordinate
        let title = feature.title ?? "Selected Location"
        
        // 1. Try Foursquare Lookup
        if let fsqService = Services.shared.foursquareService {
            do {
                let results = try await fsqService.search(query: title, location: coordinate, limit: 1)
                if let bestMatch = results.first {
                    await MainActor.run {
                        viewModel.selectPlace(bestMatch)
                        dismiss()
                    }
                    return
                }
            } catch {
                print("Foursquare lookup failed: \(error)")
            }
        }
        
        // 2. MapKit Fallback
        let placeData = EnrichmentData(
            title: title,
            descriptionText: "Apple Maps Location",
            categories: ["Point of Interest"],
            location: title,
            placeContext: PlaceContext(
                name: title,
                categories: ["POI"],
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
        await MainActor.run {
            viewModel.selectPlace(placeData)
            dismiss()
        }
    }
    
    private func searchHere() async {
        isLoading = true
        defer { isLoading = false }
        
        let center = visibleRegion?.center ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        
        // Foursquare
        if let service = Services.shared.foursquareService {
            do {
                let results: [EnrichmentData]
                if searchText.isEmpty {
                    results = try await service.searchNearby(location: center, limit: 20)
                } else {
                    results = try await service.search(query: searchText, location: center, limit: 20)
                }
                
                await MainActor.run {
                    viewModel.placeCandidates = results
                }
                return
            } catch {
                print("Foursquare search failed, trying fallback: \(error)")
            }
        }
    
        // MapKit Fallback
        if let service = Services.shared.mapKitService {
             do {
                let results: [EnrichmentData]
                if searchText.isEmpty {
                     results = try await service.searchNearby(location: center, limit: 20)
                } else {
                     results = try await service.search(query: searchText, location: center, limit: 20)
                }
                
                await MainActor.run {
                    viewModel.placeCandidates = results
                }
            } catch {
                print("MapKit search failed: \(error)")
            }
        }
    }
}
