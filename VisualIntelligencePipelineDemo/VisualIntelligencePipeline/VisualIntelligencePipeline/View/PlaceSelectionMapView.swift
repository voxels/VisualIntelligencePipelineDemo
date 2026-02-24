import SwiftUI
import MapKit
import DiverKit
import DiverShared

struct PlaceSelectionMapView: View {
    var viewModel: VisualIntelligenceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedDetail: EnrichmentData?
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var contactAddresses: [ContactAddress] = []
    @State private var isLoadingContacts = false
    
    init(viewModel: VisualIntelligenceViewModel) {
        self.viewModel = viewModel
        
        if let coordinate = viewModel.currentCaptureCoordinate {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
        } else {
            self._position = State(initialValue: .automatic)
        }
    }

    /// Contacts filtered by search text
    private var filteredContactAddresses: [ContactAddress] {
        guard !searchText.isEmpty else { return Array(contactAddresses.prefix(20)) }
        let lowercasedSearch = searchText.lowercased()
        return Array(contactAddresses.filter { contact in
            contact.contactName.lowercased().contains(lowercasedSearch) ||
            contact.formattedAddress.lowercased().contains(lowercasedSearch)
        }.prefix(20))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Map Section
                mapSection
                    .frame(height: 280)
                
                Divider()
                
                // Places and Contacts List
                placesListSection
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
                await loadContactAddresses()
            }
            .onAppear {
                setupInitialPosition()
            }
        }
    }
    
    // MARK: - Map Section
    private var mapSection: some View {
        MapReader { reader in
            Map(position: $position) {
                // Place Candidates
                ForEach(viewModel.placeCandidates, id: \.id) { candidate in
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
                
                // Contact Address Markers
                ForEach(filteredContactAddresses) { contact in
                    if let location = contact.location {
                        Annotation(contact.displayTitle, coordinate: location.coordinate) {
                            Button {
                                selectContactAddress(contact)
                            } label: {
                                Image(systemName: "person.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                    .background(Color.white.clipShape(Circle()))
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange { context in
                visibleRegion = context.region
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Task {
                        await searchHere()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Search Here")
                    }
                    .padding(8)
                    .background(.thickMaterial)
                    .cornerRadius(8)
                    .shadow(radius: 2)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Places List Section
    private var placesListSection: some View {
        List {
            // MapKit Places
            if !viewModel.placeCandidates.isEmpty {
                Section {
                    ForEach(viewModel.placeCandidates, id: \.id) { place in
                        placeRow(place)
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
        }
        .listStyle(.insetGrouped)
    }
    
    private func placeRow(_ place: EnrichmentData) -> some View {
        Button {
            viewModel.selectPlace(place)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.title ?? "Unknown Place")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let address = place.placeContext?.address ?? place.location {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
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
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m away", meters)
        } else {
            return String(format: "%.1f km away", meters / 1000)
        }
    }
    
    // MARK: - Actions
    
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
        
        viewModel.selectPlace(enrichmentData)
        dismiss()
    }
    
    private func loadContactAddresses() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        
        // Get reference location for sorting
        var referenceLocation: CLLocation?
        if let coord = viewModel.currentCaptureCoordinate {
            referenceLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        } else {
            referenceLocation = await Services.shared.locationService?.getCurrentLocation()
        }
        
        let addresses = await Services.shared.contactService?.fetchContactsWithAddresses(sortedByDistanceFrom: referenceLocation) ?? []
        
        await MainActor.run {
            contactAddresses = addresses
        }
    }
    
    private func setupInitialPosition() {
        // Only run async lookup if we didn't have a coordinate to start with
        if case .automatic = position {
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
        
        var center = visibleRegion?.center
        if center == nil { center = viewModel.currentCaptureCoordinate }
        if center == nil { center = await Services.shared.locationService?.getCurrentLocation()?.coordinate }
        
        guard let searchCenter = center else {
            print("⚠️ PlaceSelectionMap: Location unknown. Skipping search.")
            return
        }
        
        let results = await LocationSearchAggregator.fetchCandidates(
            query: searchText,
            center: searchCenter,
            mapKitService: Services.shared.mapKitService
        )
        
        await MainActor.run {
            viewModel.placeCandidates = results
        }
    }
}

