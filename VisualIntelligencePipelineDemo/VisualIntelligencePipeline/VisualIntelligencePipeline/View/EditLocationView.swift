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
    
    @State private var fsqCandidates: [EnrichmentData] = []
    @State private var mkCandidates: [EnrichmentData] = []
    // Legacy support: candidates property computed or removed?
    // We'll keep candidates as a computed property for the specific map logic if needed, but better to just iterate both.
    var candidates: [EnrichmentData] { fsqCandidates + mkCandidates }
    @State private var isLoading = false
    @State private var selectedCandidate: EnrichmentData?
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var searchText = ""
    @State private var hasZoomedToSession = false
    @State private var isUpdating = false
    @State private var selectedMapFeature: MapFeature?
    
    @Query private var sessions: [DiverSession]
    
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
                Section {
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
                        
                        // Explicitly render selected candidate if it's not in the candidate list
                        if let selected = selectedCandidate, 
                           let lat = selected.placeContext?.latitude, 
                           let lon = selected.placeContext?.longitude,
                           !candidates.contains(where: { matchesSelection($0) }) {
                            
                            Annotation(selected.title ?? "Selected", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                Button {
                                    // Already selected
                                } label: {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.green)
                                        .background(.white)
                                        .clipShape(Circle())
                                        .shadow(radius: 2)
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
                        // "Search Here" button
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
                    .contentShape(Rectangle()) // Make full row tappable
                    .onTapGesture {
                        if let loc = itemLocationCoordinate {
                            withAnimation {
                                position = .region(MKCoordinateRegion(center: loc, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                            }
                        }
                    }
                }
                
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
                ProgressView("Updating Context...")
                .padding()
                .background(.regularMaterial)
                .cornerRadius(10)
            }
        }
    }
    
    private func setupInitialPosition() {
        Task {
            // 1. Determine Map Position
            if let loc = itemLocationCoordinate {
                await MainActor.run {
                    position = .region(MKCoordinateRegion(center: loc, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                }
            } else if let sl = sessionLocation {
                await MainActor.run {
                    position = .region(MKCoordinateRegion(center: sl, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
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
                    // Default to SF only if location services fail/unavailable
                    await MainActor.run {
                        // Default to World View or Invalid, do NOT use SF.
                        print("⚠️ EditLocationView: Location unknown. Defaulting to world view.")
                        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180)))
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
                    self.fsqCandidates = [currentPlace] // Default to FSQ list?
                }
            }
            
            // 3. Trigger nearby search AFTER position is set
            // Short sleep to allow Map to update its region binding?
            // Actually, we can pass the explicit center we just calculated to fetchCandidates to be safe
            // regardless of whether visibleRegion has updated yet.
            
            // Re-calculate the center we just decided on
            if let loc = itemLocationCoordinate { 
                await fetchCandidates(explicitCenter: loc)
            } else if let sl = sessionLocation { 
                await fetchCandidates(explicitCenter: sl)
            } else if let current = await Services.shared.locationService?.getCurrentLocation()?.coordinate { 
                await fetchCandidates(explicitCenter: current)
            } else {
                // If we defaulted to SF (Hardcoded), do NOT trigger an expensive/irrelevant API search.
                // Just leave candidates empty.
                print("⚠️ Location unknown. Skipping automatic place search.")
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
            }
        }
    }
    
    private func fetchCandidates(explicitCenter: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        // Prioritize map center if visible, otherwise item location
        let searchCenter = explicitCenter ?? visibleRegion?.center ?? itemLocationCoordinate ?? sessionLocation
        
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
    
    private func updateLocation() async {
        guard let candidate = selectedCandidate else { return }
        
        isUpdating = true
        
        // Ensure we capture all necessary data before any potential view recycling
        let newContext = candidate.placeContext
        let newCategories = candidate.categories
        let newLocation = (newContext?.latitude != nil && newContext?.longitude != nil) ? "\(newContext!.latitude!),\(newContext!.longitude!)" : nil
        
        await MainActor.run {
            // 1. Update Core Metadata
            // Improve "Old Name" detection: Look at placeContext first, but fall back to item.title if it's specific
            let currentTitle = item.title
            let isGenericTitle = ["Home", "Unknown Place", "Current Location", item.location, ""].contains(currentTitle ?? "")
            let oldName = item.placeContext?.name ?? (isGenericTitle ? nil : currentTitle)

            var finalContext = newContext
            
            // Smart Merge: If new name looks like an address (starts with number) AND old name was valid, preserve old name
            if let newName = newContext?.name, let old = oldName, !old.isEmpty, old != "Unknown Place" {
                // Heuristic: If new name looks like an address...
                // Regex: Starts with 1+ digits, followed by space, then letters.
                let isAddressLike = newName.range(of: "^\\d+\\s+[A-Za-z]+", options: .regularExpression) != nil
                // And old name does NOT look like an address (to prevent preserving "123 Main St" over "125 Main St")
                let oldIsAddressLike = old.range(of: "^\\d+\\s+[A-Za-z]+", options: .regularExpression) != nil
                
                if isAddressLike && !oldIsAddressLike {
                     print("ℹ️ Preserving old name '\(old)' because new name '\(newName)' looks like an address.")
                     
                     // Create new context with old name but everything else from newContext
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
                             tips: nc.tips
                         )
                     }
                }
            }
            
            item.placeContext = finalContext
            
            // Smart Title Update: Only if we didn't preserve the old name effectively
            if let newName = finalContext?.name {
                let current = item.title ?? ""
                let candidates = ["Home", "Unknown Place", "Current Location", oldName, item.location].compactMap { $0 }
                if current.isEmpty || candidates.contains(current) {
                    item.title = newName
                }
            }
            if let loc = newLocation {
                item.location = loc
            }
            item.categories = newCategories
            
            // Critical: Reset purposes/intent to force fresh regeneration based on new place
            item.purposes = []
            
            // 2. Persist
            // CRITICAL: Update linked Session immediately to "lock in" this location against reprocessing overrides
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
            
            // 3. Trigger SILENT background reprocessing
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
        
        // 1. Direct ID Match
        if selected.id == candidate.id { return true }
        
        // 2. Loose Match (Title + Location) to handle ID drift between API calls
        let titlesMatch = (selected.title == candidate.title)
        
        var locationsMatch = false
        if let l1 = selected.placeContext, let l2 = candidate.placeContext,
           let lat1 = l1.latitude, let lon1 = l1.longitude,
           let lat2 = l2.latitude, let lon2 = l2.longitude {
            // Approx 10 meters tolerance (0.0001 deg is ~11m)
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
