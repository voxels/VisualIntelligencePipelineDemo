import SwiftUI
import MapKit
import SwiftData
import DiverKit
import DiverShared

struct EditLocationView: View {
    @Bindable var item: ProcessedItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.metadataPipelineService) private var pipelineService
    
    @State private var candidates: [EnrichmentData] = []
    @State private var contactAddresses: [ContactAddress] = []
    @State private var isLoading = false
    @State private var isLoadingContacts = false
    @State private var selectedCandidate: EnrichmentData?
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var searchText = ""
    @State private var hasZoomedToSession = false
    @State private var isUpdating = false
    @State private var selectedMapFeature: MapFeature?
    
    @Query private var sessions: [DiverSession]
    
    init(item: ProcessedItem) {
        self.item = item
        
        // Synchronously determine initial position from available context
        let initialCoord: CLLocationCoordinate2D? = {
            // Priority 1: Structured Place Context
            if let ctx = item.placeContext, let lat = ctx.latitude, let lon = ctx.longitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            
            // Priority 2: Parsed Location String
            if let locString = item.location {
                let components = locString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if components.count == 2,
                   let lat = Double(components[0]),
                   let lon = Double(components[1]) {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
            
            // Fallback: This will jump if we don't have item-specific data, but it's better than world view
            return nil
        }()
        
        if let coord = initialCoord {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
        } else {
            // Default to automatic which might be user location if enabled
            self._position = State(initialValue: .automatic)
        }
    }
    /// Contacts filtered by search text
    private var filteredContactAddresses: [ContactAddress] {
        guard !searchText.isEmpty else { return contactAddresses }
        let lowercasedSearch = searchText.lowercased()
        return contactAddresses.filter { contact in
            contact.contactName.lowercased().contains(lowercasedSearch) ||
            contact.formattedAddress.lowercased().contains(lowercasedSearch)
        }
    }
    
    private var sessionLocation: CLLocationCoordinate2D? {
        if let sessionID = item.sessionID, let session = sessions.first(where: { $0.sessionID == sessionID }),
           let lat = session.latitude, let lon = session.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    private var itemLocationCoordinate: CLLocationCoordinate2D? {
        // Priority 1: Structured Place Context
        if let ctx = item.placeContext, let lat = ctx.latitude, let lon = ctx.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // Priority 2: Parsed Location String (e.g. "37.7,-122.4")
        if let locString = item.location {
            let components = locString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count == 2,
               let lat = Double(components[0]),
               let lon = Double(components[1]) {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Map Section
                Section {
                    mapSection
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                }
                
                // Current Location
                Section("Current Location") {
                    VStack(alignment: .leading) {
                        Text(item.placeContext?.name ?? item.location ?? "Unknown Place")
                            .font(.headline)
                        Text(item.location ?? "No Coordinates")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let pid = item.placeContext?.placeID {
                            Text("ID: \(pid)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let loc = itemLocationCoordinate {
                            withAnimation {
                                position = .region(MKCoordinateRegion(center: loc, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                            }
                        }
                    }
                }
                
                // Selected Location
                if let selected = selectedCandidate {
                    Section("Selected Location") {
                        VStack(alignment: .leading) {
                             Text(selected.title ?? "New Selection")
                                 .font(.headline)
                                 .foregroundStyle(.green)
                             
                             if !selected.categories.isEmpty {
                                 Text(selected.categories.joined(separator: ", "))
                                     .font(.subheadline)
                                     .foregroundStyle(.secondary)
                             }
                             
                             if let loc = selected.location {
                                 Text(loc)
                                     .font(.caption)
                                     .foregroundStyle(.tertiary)
                             }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let lat = selected.placeContext?.latitude, let lon = selected.placeContext?.longitude {
                                withAnimation {
                                    position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                                }
                            }
                        }
                    }
                }
                
                // Places (MapKit-primary)
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
            .navigationTitle("Edit Location")
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
                ProgressView("Updating Context...")
                .padding()
                .glassEffect()
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Map Section
    private var mapSection: some View {
        Map(position: $position, selection: $selectedMapFeature) {
            // Current Item Location
            if let loc = itemLocationCoordinate {
                Marker("Current", coordinate: loc)
                    .tint(.purple)
            }
            
            // Session Location (if different)
            if let sl = sessionLocation, sl.latitude != itemLocationCoordinate?.latitude {
                 Marker("Session", coordinate: sl)
                    .tint(.gray)
            }
            
            // Place Candidates
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
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange { context in
            visibleRegion = context.region
        }
        .onChange(of: selectedMapFeature) {_, feature in
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
    
    // MARK: - Contact Row
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
        
        selectedCandidate = enrichmentData
        
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
    }
    
    private func setupInitialPosition() {
        Task {
            // 1. If we don't have a specific position yet, try session or current location
            if case .automatic = position {
                if let sl = sessionLocation {
                    await MainActor.run {
                        withAnimation {
                            position = .region(MKCoordinateRegion(center: sl, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                        }
                    }
                } else {
                    if let current = await Services.shared.locationService?.getCurrentLocation() {
                         await MainActor.run {
                             withAnimation {
                                 position = .region(MKCoordinateRegion(center: current.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                             }
                         }
                    }
                }
            }
            
            // 2. Initial selection from context
            if let context = item.placeContext {
                let currentPlace = EnrichmentData(
                    title: context.name,
                    descriptionText: item.summary ?? "Current Location",
                    categories: item.categories,
                    location: item.location,
                    placeContext: context
                )
                await MainActor.run {
                    self.selectedCandidate = currentPlace
                }
            }
            
            // 3. Trigger nearby search
            if let loc = itemLocationCoordinate { 
                await fetchCandidates(explicitCenter: loc)
            } else if let sl = sessionLocation { 
                await fetchCandidates(explicitCenter: sl)
            } else if let current = await Services.shared.locationService?.getCurrentLocation()?.coordinate { 
                await fetchCandidates(explicitCenter: current)
            } else {
                print("⚠️ Location unknown. Skipping automatic place search.")
            }
            
            // 4. Load contact addresses
            await loadContactAddresses()
        }
    }
    
    private func loadContactAddresses() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        
        // Get reference location for sorting
        var referenceLocation: CLLocation?
        if let coord = itemLocationCoordinate {
            referenceLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        } else if let sl = sessionLocation {
            referenceLocation = CLLocation(latitude: sl.latitude, longitude: sl.longitude)
        } else {
            referenceLocation = await Services.shared.locationService?.getCurrentLocation()
        }
        
        let addresses = await Services.shared.contactService?.fetchContactsWithAddresses(sortedByDistanceFrom: referenceLocation) ?? []
        
        await MainActor.run {
            contactAddresses = addresses
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
            }
        }
    }
    
    private func fetchCandidates(explicitCenter: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        let searchCenter = explicitCenter ?? visibleRegion?.center ?? itemLocationCoordinate ?? sessionLocation
        
        guard let center = searchCenter else { return }
        
        // Use LocationSearchAggregator for MapKit-primary search
        let results = await LocationSearchAggregator.fetchCandidates(
            query: searchText,
            center: center,
            foursquareService: Services.shared.foursquareService,
            mapKitService: Services.shared.mapKitService
        )

        await MainActor.run {
            self.candidates = results
        }
    }
    
    private func updateLocation() async {
        guard let candidate = selectedCandidate else { return }
        
        isUpdating = true
        
        let newContext = candidate.placeContext
        let newCategories = candidate.categories
        let newLocation = (newContext?.latitude != nil && newContext?.longitude != nil) ? "\(newContext!.latitude!),\(newContext!.longitude!)" : nil
        
        await MainActor.run {
            // 1. Update Core Metadata
            let currentTitle = item.title
            let isGenericTitle = ["Home", "Unknown Place", "Current Location", item.location, ""].contains(currentTitle ?? "")
            let oldName = item.placeContext?.name ?? (isGenericTitle ? nil : currentTitle)

            var finalContext = newContext
            
            // Smart Merge: If new name looks like an address AND old name was valid, preserve old name
            if let newName = newContext?.name, let old = oldName, !old.isEmpty, old != "Unknown Place" {
                let isAddressLike = newName.range(of: "^\\d+\\s+[A-Za-z]+", options: .regularExpression) != nil
                let oldIsAddressLike = old.range(of: "^\\d+\\s+[A-Za-z]+", options: .regularExpression) != nil
                
                if isAddressLike && !oldIsAddressLike {
                     print("ℹ️ Preserving old name '\(old)' because new name '\(newName)' looks like an address.")
                     
                     if let nc = newContext {
                         finalContext = PlaceContext(
                             name: old,
                             categories: nc.categories,
                             placeID: nc.placeID,
                             address: nc.address,
                             rating: nc.rating,
                             isOpen: nc.isOpen,
                             latitude: nc.latitude,
                             longitude: nc.longitude,
                             priceLevel: nc.priceLevel,
                             phoneNumber: nc.phoneNumber,
                             website: nc.website,
                             photos: nc.photos,
                             tips: nc.tips,
                             contactIdentifier: nc.contactIdentifier
                         )
                     }
                }
            }
            
            item.placeContext = finalContext
            
            // Smart Title Update
            if let newName = finalContext?.name {
                let current = item.title ?? ""
                let genericCandidates = ["Home", "Unknown Place", "Current Location", oldName, item.location].compactMap { $0 }
                if current.isEmpty || genericCandidates.contains(current) {
                    item.title = newName
                }
            }
            if let loc = newLocation {
                item.location = loc
            }
            item.categories = newCategories
            
            // Reset purposes for fresh regeneration
            item.purposes = []
            
            // 2. Update linked Session
            if let sessionID = item.sessionID, let session = sessions.first(where: { $0.sessionID == sessionID }) {
                print("🔒 Locking in session location override: \(newContext?.name ?? "nil")")
                session.locationName = newContext?.name
                session.placeID = newContext?.placeID
                if let lat = newContext?.latitude, let lon = newContext?.longitude {
                    session.latitude = lat
                    session.longitude = lon
                }
            }
            
            do {
                try modelContext.save()
                print("✅ Location updated and saved for \(item.id)")
            } catch {
                print("❌ Failed to save item after location update: \(error)")
            }
            
            // 3. Trigger background reprocessing
            Task {
                try? await pipelineService?.processItemImmediately(item)
            }
            
            // 4. Finalize UI state and dismiss
            isUpdating = false
            dismiss()
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
    
    private func matchesSelection(_ candidate: EnrichmentData) -> Bool {
        guard let selected = selectedCandidate else { return false }
        
        if selected.id == candidate.id { return true }
        
        let titlesMatch = (selected.title == candidate.title)
        
        var locationsMatch = false
        if let l1 = selected.placeContext, let l2 = candidate.placeContext,
           let lat1 = l1.latitude, let lon1 = l1.longitude,
           let lat2 = l2.latitude, let lon2 = l2.longitude {
            locationsMatch = abs(lat1 - lat2) < 0.0001 && abs(lon1 - lon2) < 0.0001
        }
        
        return titlesMatch && locationsMatch
    }
}

struct LocationCandidateRow: View {
    let candidate: EnrichmentData
    let selectedID: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
             HStack {
                 VStack(alignment: .leading) {
                     Text(candidate.title ?? "Unknown")
                         .font(.body)
                         .foregroundStyle(.primary)
                     if !candidate.categories.isEmpty {
                         Text(candidate.categories.joined(separator: ", "))
                             .font(.caption)
                             .foregroundStyle(.secondary)
                     }
                 }
                 Spacer()
                 if selectedID == candidate.id {
                     Image(systemName: "checkmark")
                         .foregroundStyle(.blue)
                 }
             }
         }
         .buttonStyle(.plain)
    }
}

