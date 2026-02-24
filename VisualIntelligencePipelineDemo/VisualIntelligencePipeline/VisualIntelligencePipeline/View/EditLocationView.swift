import SwiftUI
import MapKit
import SwiftData
import DiverKit
import DiverShared

// MARK: - Unified Location Edit Target

/// Enum-based target so one view handles both item-level and session-level edits.
enum LocationEditTarget {
    case item(ProcessedItem)
    case session(SessionMetadata)
    
    var navigationTitle: String {
        switch self {
        case .item: return "Edit Location"
        case .session: return "Edit Session Location"
        }
    }
    
    var currentLocationName: String {
        switch self {
        case .item(let item):
            return item.placeContext?.name ?? item.location ?? "Unknown Place"
        case .session(let session):
            return session.locationName ?? "Unknown Place"
        }
    }
    
    var currentLocationDetail: String {
        switch self {
        case .item(let item):
            return item.location ?? "No Coordinates"
        case .session(let session):
            if let lat = session.latitude, let lon = session.longitude {
                return "\(lat), \(lon)"
            }
            return "No Coordinates"
        }
    }
    
    var placeIDDetail: String? {
        switch self {
        case .item(let item): return item.placeContext?.placeID
        case .session: return nil
        }
    }
    
    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .item(let item):
            if let ctx = item.placeContext, let lat = ctx.latitude, let lon = ctx.longitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            if let locString = item.location {
                let components = locString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if components.count == 2, let lat = Double(components[0]), let lon = Double(components[1]) {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
            return nil
        case .session(let session):
            if let lat = session.latitude, let lon = session.longitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return nil
        }
    }
    
    var existingPlaceContext: PlaceContext? {
        switch self {
        case .item(let item): return item.placeContext
        case .session: return nil
        }
    }
    
    var categories: [String] {
        switch self {
        case .item(let item): return item.categories
        case .session: return []
        }
    }
    
    var sessionID: String? {
        switch self {
        case .item(let item): return item.sessionID
        case .session(let session): return session.sessionID
        }
    }
}

struct EditLocationView: View {
    let target: LocationEditTarget
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
    @State private var isUpdating = false
    @State private var selectedMapFeature: MapFeature?
    
    @Query private var sessions: [SessionMetadata]
    
    /// Convenience initializer for ProcessedItem
    init(item: ProcessedItem) {
        self.target = .item(item)
        
        if let coord = LocationEditTarget.item(item).coordinate {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
        } else {
            self._position = State(initialValue: .automatic)
        }
    }
    
    /// Convenience initializer for SessionMetadata
    init(session: SessionMetadata) {
        self.target = .session(session)
        
        if let coord = LocationEditTarget.session(session).coordinate {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
        } else {
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
    
    /// Session location (for item-level edits, shows context from parent session)
    private var sessionLocation: CLLocationCoordinate2D? {
        switch target {
        case .item(let item):
            if let sessionID = item.sessionID, let session = sessions.first(where: { $0.sessionID == sessionID }),
               let lat = session.latitude, let lon = session.longitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return nil
        case .session:
            return nil
        }
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
                        Text(target.currentLocationName)
                            .font(.headline)
                        Text(target.currentLocationDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let pid = target.placeIDDetail {
                            Text("ID: \(pid)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let loc = target.coordinate {
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
                
                // Contact Addresses
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
            .navigationTitle(target.navigationTitle)
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
                ProgressView("Updating...")
                .padding()
                .glassEffect()
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Map Section
    private var mapSection: some View {
        Map(position: $position, selection: $selectedMapFeature) {
            // Current Location
            if let loc = target.coordinate {
                Marker("Current", coordinate: loc)
                    .tint(.purple)
            }
            
            // Session Location (item-level only, if different from item)
            if let sl = sessionLocation, sl.latitude != target.coordinate?.latitude {
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
            // 1. Map Position — use target coordinate, session, or current location
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
            
            // 2. Initial selection from existing context (item-level only)
            if let context = target.existingPlaceContext {
                let summary: String
                switch target {
                case .item(let item): summary = item.summary ?? "Current Location"
                case .session: summary = "Current Location"
                }
                let currentPlace = EnrichmentData(
                    title: context.name,
                    descriptionText: summary,
                    categories: target.categories,
                    location: target.currentLocationDetail,
                    placeContext: context
                )
                await MainActor.run {
                    self.selectedCandidate = currentPlace
                }
            }
            
            // 3. Trigger nearby search
            if let loc = target.coordinate { 
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
        
        var referenceLocation: CLLocation?
        if let coord = target.coordinate {
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
        
        let searchCenter = explicitCenter ?? visibleRegion?.center ?? target.coordinate ?? sessionLocation
        
        guard let center = searchCenter else { return }
        
        let results = await LocationSearchAggregator.fetchCandidates(
            query: searchText,
            center: center,
            mapKitService: Services.shared.mapKitService
        )

        await MainActor.run {
            self.candidates = results
        }
    }
    
    // MARK: - Update Location (target-specific)
    
    private func updateLocation() async {
        guard let candidate = selectedCandidate else { return }
        
        isUpdating = true
        
        switch target {
        case .item(let item):
            await updateItemLocation(item: item, candidate: candidate)
        case .session(let session):
            await updateSessionLocation(session: session, candidate: candidate)
        }
    }
    
    /// Item-level update: updates item fields + linked session
    private func updateItemLocation(item: ProcessedItem, candidate: EnrichmentData) async {
        let newContext = candidate.placeContext
        let newCategories = candidate.categories
        let newLocation = (newContext?.latitude != nil && newContext?.longitude != nil) ? "\(newContext!.latitude!),\(newContext!.longitude!)" : nil
        
        await MainActor.run {
            // 1. Smart Name Merge
            let currentTitle = item.title
            let isGenericTitle = ["Home", "Unknown Place", "Current Location", item.location, ""].contains(currentTitle ?? "")
            let oldName = item.placeContext?.name ?? (isGenericTitle ? nil : currentTitle)

            var finalContext = newContext
            
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
            
            isUpdating = false
            dismiss()
            
            // 3. Trigger background reprocessing AFTER dismiss
            let reprocessID = item.id
            Task.detached(priority: .utility) { [pipelineService] in
                try? await pipelineService?.processItemByID(reprocessID)
            }
        }
    }
    
    /// Session-level update: updates session + all child items
    private func updateSessionLocation(session: SessionMetadata, candidate: EnrichmentData) async {
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
            var itemIDs: [String] = []
            if let items = try? modelContext.fetch(descriptor) {
                for item in items {
                    item.placeContext = candidate.placeContext
                    if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                        item.location = "\(lat),\(lon)"
                    }
                    item.categories = candidate.categories
                    item.purposes = []
                    itemIDs.append(item.id)
                }
            }
            
            try? modelContext.save()
            isUpdating = false
            dismiss()
            
            // Reprocess all items SEQUENTIALLY in background AFTER dismiss.
            // Each processItemByID creates its own ModelContext, avoiding
            // the EXC_BAD_ACCESS crash from concurrent shared-context mutations.
            Task.detached(priority: .utility) { [pipelineService] in
                for id in itemIDs {
                    try? await pipelineService?.processItemByID(id)
                }
            }
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
