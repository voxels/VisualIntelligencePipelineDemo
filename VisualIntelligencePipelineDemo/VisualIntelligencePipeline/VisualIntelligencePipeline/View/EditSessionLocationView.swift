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
    
    @State private var candidates: [EnrichmentData] = []
    @State private var contactAddresses: [ContactAddress] = []
    @State private var isLoadingContacts = false
    // Legacy support
    // Legacy support removal
    // var candidates: [EnrichmentData] { fsqCandidates + mkCandidates }
    @State private var isLoading = false
    @State private var selectedCandidate: EnrichmentData?
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?

    @State private var searchText = ""
    
    /// Contacts filtered by search text
    private var filteredContactAddresses: [ContactAddress] {
        guard !searchText.isEmpty else { return contactAddresses }
        let lowercasedSearch = searchText.lowercased()
        return contactAddresses.filter { contact in
            contact.contactName.lowercased().contains(lowercasedSearch) ||
            contact.formattedAddress.lowercased().contains(lowercasedSearch)
        }
    }
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
                        ForEach(candidates) { candidate in
                            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                let isSelected = matchesSelection(candidate)
                                
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
                        
                        // Contact Address Markers
                        ForEach(filteredContactAddresses) { contact in
                            if let location = contact.location {
                                Annotation(contact.displayTitle, coordinate: location.coordinate) {
                                    Button {
                                        selectContactAddress(contact)
                                    } label: {
                                        Image(systemName: "person.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(.blue)
                                            .background(.white)
                                            .clipShape(Circle())
                                            .shadow(radius: 2)
                                    }
                                }
                            }
                        }
                        
                        // Selected candidate marker (if not in candidates list)
                        if let selected = selectedCandidate, 
                           let lat = selected.placeContext?.latitude, 
                           let lon = selected.placeContext?.longitude,
                           !candidates.contains(where: { matchesSelection($0) }) {
                            
                            Annotation(selected.title ?? "Selected", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.green)
                                    .background(.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
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
                    .onChange(of: selectedMapFeature) { _, feature in
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
                
                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { candidate in
                            LocationCandidateRow(candidate: candidate, selectedID: selectedCandidate?.id) {
                                selectCandidate(candidate)
                            }
                        }
                    } header: {
                        Label("Places", systemImage: "mappin.and.ellipse")
                    }
                }
                
                // Contact Addresses (at bottom)
                if !filteredContactAddresses.isEmpty {
                    Section {
                        ForEach(filteredContactAddresses) { contact in
                            contactRow(contact)
                        }
                    } header: {
                        Label("Contacts", systemImage: "person.2.fill")
                    } footer: {
                        Text("Sorted by distance from current location")
                            .font(.caption2)
                    }
                } else if isLoadingContacts {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading contacts...")
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                         Label("Contacts", systemImage: "person.2.fill")
                    }
                }
                
                if candidates.isEmpty && filteredContactAddresses.isEmpty && !isLoading && !isLoadingContacts {
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
            
            
            // 3. Trigger nearby search
            if let loc = sessionLocationCoordinate { 
                await fetchCandidates(explicitCenter: loc)
            } else if let current = await Services.shared.locationService?.getCurrentLocation()?.coordinate { 
                await fetchCandidates(explicitCenter: current)
            } else {
                print("⚠️ Session Location unknown. Skipping automatic place search.")
            }
            
            // 4. Load contact addresses
            await loadContactAddresses()
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
                self.candidates = [data]
            }
        }
    }
    
    private func loadContactAddresses() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        
        // Get reference location for sorting
        var referenceLocation: CLLocation?
        if let coord = sessionLocationCoordinate {
            referenceLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        } else {
            referenceLocation = await Services.shared.locationService?.getCurrentLocation()
        }
        
        let addresses = await Services.shared.contactService?.fetchContactsWithAddresses(sortedByDistanceFrom: referenceLocation) ?? []
        
        await MainActor.run {
            contactAddresses = addresses
        }
    }
    
    private func fetchCandidates(explicitCenter: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        let searchCenter = explicitCenter ?? visibleRegion?.center ?? sessionLocationCoordinate
        guard let center = searchCenter else { return }
        
        // Use LocationSearchAggregator for MapKit-primary search (Foursquare removed)
        let results = await LocationSearchAggregator.fetchCandidates(
            query: searchText,
            center: center,
            foursquareService: nil, // DISABLE Foursquare explicitly
            mapKitService: Services.shared.mapKitService
        )

        await MainActor.run {
            self.candidates = results
        }
    }
    
    private func matchesSelection(_ candidate: EnrichmentData) -> Bool {
        guard let selected = selectedCandidate else { return false }
        if selected.id == candidate.id { return true }
        return selected.title == candidate.title
    }
    
    // MARK: - Contact Actions
    
    private func contactRow(_ contact: ContactAddress) -> some View {
        Button {
            selectContactAddress(contact)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.displayTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(contact.formattedAddress.replacingOccurrences(of: "\n", with: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let distance = contact.distance {
                        Text(formatDistance(distance))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if let selected = selectedCandidate,
                   selected.placeContext?.contactIdentifier == contact.contactIdentifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m away", meters)
        } else {
            return String(format: "%.1f km away", meters / 1000)
        }
    }
    
    private func selectContactAddress(_ contact: ContactAddress) {
        guard let location = contact.location else { return }
        
        let enrichmentData = EnrichmentData(
            title: contact.displayTitle,
            descriptionText: contact.formattedAddress,
            categories: ["Contact"],
            location: contact.formattedAddress,
            placeContext: PlaceContext(
                name: contact.displayTitle,
                categories: ["Contact Address"],
                address: contact.formattedAddress,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                contactIdentifier: contact.contactIdentifier
            )
        )
        
        selectedCandidate = enrichmentData
        
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
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
