import SwiftUI
import MapKit
import SwiftData
import DiverKit
import DiverShared

struct EditSessionLocationView: View {
    @Bindable var session: DiverSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.metadataPipelineService) private var pipelineService
    
    @State private var fsqCandidates: [EnrichmentData] = []
    @State private var mkCandidates: [EnrichmentData] = []
    // Legacy support
    var candidates: [EnrichmentData] { fsqCandidates + mkCandidates }
    @State private var isLoading = false
    @State private var selectedCandidate: EnrichmentData?
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var searchText = ""
    @State private var isUpdating = false
    @State private var selectedMapFeature: MapFeature?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map(position: $position, selection: $selectedMapFeature) {
                        // Current Session Location
                        if let loc = sessionLocationCoordinate {
                            Marker("Current", coordinate: loc)
                                .tint(.gray)
                        }
                        
                        // Candidates
                        ForEach(candidates, id: \.placeContext?.placeID) { candidate in
                            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                let isSelected = selectedCandidate?.placeContext?.placeID == candidate.placeContext?.placeID
                                
                                Annotation(candidate.title ?? "Unknown", coordinate: coordinate) {
                                    Button {
                                        selectCandidate(candidate)
                                    } label: {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(isSelected ? .green : .red)
                                            .background(.white)
                                            .clipShape(Circle())
                                            .shadow(radius: 2)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .onMapCameraChange { context in
                        visibleRegion = context.region
                    }
                    .onChange(of: selectedMapFeature) { feature in
                        if let feature {
                            Task { await resolveMapFeature(feature) }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            Task { await fetchCandidates() }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 2)
                        }
                        .padding()
                    }
                }
                
                Section("Current Location") {
                    VStack(alignment: .leading) {
                        Text(session.locationName ?? "Unknown Place")
                            .font(.headline)
                        if let lat = session.latitude, let lon = session.longitude {
                            Text("\(lat), \(lon)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No Coordinates")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if !fsqCandidates.isEmpty {
                    Section("Foursquare Places") {
                        ForEach(fsqCandidates) { candidate in
                            LocationCandidateRow(candidate: candidate, selectedID: selectedCandidate?.id) {
                                selectCandidate(candidate)
                            }
                        }
                    }
                }
                
                if !mkCandidates.isEmpty {
                    Section("Apple Maps") {
                        ForEach(mkCandidates) { candidate in
                            LocationCandidateRow(candidate: candidate, selectedID: selectedCandidate?.id) {
                                selectCandidate(candidate)
                            }
                        }
                    }
                }
                
                if fsqCandidates.isEmpty && mkCandidates.isEmpty && !isLoading {
                     Section {
                         Text("No places found nearby.")
                             .foregroundStyle(.secondary)
                     }
                }
            }
            .navigationTitle("Edit Session Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Update") {
                        Task {
                            await updateLocation()
                        }
                    }
                    .disabled(selectedCandidate == nil || isUpdating)
                }
            }
            .task(id: searchText) {
                // Skip initial load to avoid overwriting onAppear data if no search text
                if !searchText.isEmpty {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await fetchCandidates()
                }
            }
            .onAppear {
                setupInitialPosition()
            }
        }
        .disabled(isUpdating)
        .overlay {
            if isUpdating {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView("Updating Session...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
            }
        }
    }
    
    private var sessionLocationCoordinate: CLLocationCoordinate2D? {
        if let lat = session.latitude, let lon = session.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    private func setupInitialPosition() {
        Task {
            // 1. Determine Map Position & Center
            if let loc = sessionLocationCoordinate {
                await MainActor.run {
                    position = .region(MKCoordinateRegion(center: loc, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                }
            } else {
                // Attempt to get current location or default to SF
                if let current = await Services.shared.locationService?.getCurrentLocation() {
                     await MainActor.run {
                         withAnimation {
                             position = .region(MKCoordinateRegion(center: current.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                         }
                     }
                } else {
                    await MainActor.run {
                        position = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180)
                        ))
                    }
                }
            }
            
            // 3. Trigger nearby search AFTER position is set
            if let loc = sessionLocationCoordinate { 
                await fetchCandidates(explicitCenter: loc)
            } else if let current = await Services.shared.locationService?.getCurrentLocation()?.coordinate { 
                await fetchCandidates(explicitCenter: current)
            } else {
                print("⚠️ Session Location unknown. Skipping automatic place search.")
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
                self.selectedCandidate = data
                self.fsqCandidates = [data]
            }
        }
    }
    
    private func fetchCandidates(explicitCenter: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        let searchCenter = explicitCenter ?? visibleRegion?.center ?? sessionLocationCoordinate
        guard let center = searchCenter else { return }
        
        async let fsqResults = searchFoursquare(at: center)
        async let mkResults = searchMapKit(at: center)
        
        let (fsq, mk) = await (fsqResults, mkResults)

        await MainActor.run {
            self.fsqCandidates = fsq
            self.mkCandidates = mk
        }
    }
    
    private func searchFoursquare(at center: CLLocationCoordinate2D) async -> [EnrichmentData] {
        guard let service = Services.shared.foursquareService else { return [] }
        do {
            if searchText.isEmpty {
                return try await service.searchNearby(location: center, limit: 50)
            } else {
                return try await service.search(query: searchText, location: center, limit: 50)
            }
        } catch {
            print("FSQ Error: \(error)")
            return []
        }
    }
    
    private func searchMapKit(at center: CLLocationCoordinate2D) async -> [EnrichmentData] {
        guard let service = Services.shared.mapKitService else { return [] }
        do {
             if searchText.isEmpty {
                return try await service.searchNearby(location: center, limit: 50)
            } else {
                return try await service.search(query: searchText, location: center, limit: 50)
            }
        } catch {
            print("MK Error: \(error)")
            return []
        }
    }
    
    private func selectCandidate(_ candidate: EnrichmentData) {
        selectedCandidate = candidate
         if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))
            }
        }
    }
    
    private func updateLocation() async {
        guard let candidate = selectedCandidate else { return }
        isUpdating = true
        defer { isUpdating = false }
        
        await MainActor.run {
            // 1. Update Session Metadata
            session.locationName = candidate.placeContext?.name
            session.placeID = candidate.placeContext?.placeID
            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                session.latitude = lat
                session.longitude = lon
            }
            
            // 2. Update children in session and trigger reprocessing
            let targetID = session.sessionID
            let descriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == targetID })
            if let items = try? modelContext.fetch(descriptor) {
                for item in items {
                    item.placeContext = candidate.placeContext
                    if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                        item.location = "\(lat),\(lon)"
                    }
                    item.categories = candidate.categories
                    
                    // Critical: Reset purposes/intent to force fresh regeneration
                    item.purposes = []
                    
                    // Trigger silent background reprocessing for each item
                    Task {
                        try? await pipelineService?.processItemImmediately(item)
                    }
                }
            }
            
            try? modelContext.save()
            dismiss()
        }
    }
}
