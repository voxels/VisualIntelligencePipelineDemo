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
                        ForEach(candidates, id: \.placeContext?.placeID) { candidate in
                            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                let isSelected = selectedCandidate?.placeContext?.placeID == candidate.placeContext?.placeID
                                Marker(candidate.title ?? "Unknown", coordinate: coordinate)
                                    .tint(isSelected ? .green : .red)
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
                
                Section("Nearby Places") {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if candidates.isEmpty {
                        Text("No places found nearby.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.placeContext?.placeID) { candidate in
                            Button {
                                selectedCandidate = candidate
                                // Move map to candidate
                                if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                                    withAnimation {
                                        position = .region(MKCoordinateRegion(
                                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                        ))
                                    }
                                }
                            } label: {
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
                                    if selectedCandidate?.placeContext?.placeID == candidate.placeContext?.placeID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
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
                ToolbarItem(placement: .confirmationAction) {
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
        // 1. Map Position
        if let loc = itemLocationCoordinate {
            position = .region(MKCoordinateRegion(center: loc, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        } else if let sl = sessionLocation {
            position = .region(MKCoordinateRegion(center: sl, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        } else {
            // Default to SF
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
        }
        
        // 2. Initial selection from current item context
        if let context = item.placeContext {
            let currentPlace = EnrichmentData(
                title: context.name,
                descriptionText: item.summary ?? "Current Location",
                categories: item.categories,
                location: item.location,
                placeContext: context
            )
            self.selectedCandidate = currentPlace
            self.candidates = [currentPlace]
            
            // Trigger a nearby search to fill the list, but keep current selection
            Task {
                await fetchCandidates()
            }
        } else {
            // No context yet, just search nearby
            Task {
                await fetchCandidates()
            }
        }
    }
    
    private func resolveMapFeature(_ feature: MapFeature) async {
        let coordinate = feature.coordinate
        let title = feature.title ?? "Selected Location"
        
        // 1. Try Foursquare Lookup by Name/Location
        if let fsqService = Services.shared.foursquareService {
            do {
                let results = try await fsqService.search(query: title, location: coordinate, limit: 1)
                if let bestMatch = results.first {
                    await MainActor.run {
                        self.selectedCandidate = bestMatch
                        self.candidates = [bestMatch] // Focus on this one? Or append?
                    }
                    return
                }
            } catch {
                print("Foursquare lookup failed, falling back to MapKit: \(error)")
            }
        }
        
        // 2. Fallback to MapKit
        if let mapService = Services.shared.mapKitService {
             let placeData = (try? await mapService.enrich(query: title, location: coordinate)) ?? EnrichmentData(
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
                self.selectedCandidate = placeData
                // self.candidates.append(placeData) // Optional
            }
        }
    }
    
    private func fetchCandidates() async {
        isLoading = true
        defer { isLoading = false }
        
        let currentSelection = selectedCandidate
        let searchCenter = visibleRegion?.center ?? itemLocationCoordinate ?? sessionLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let query = searchText
        
        // 1. Run searches in parallel
        async let fsqTask: [EnrichmentData] = {
            if let service = Services.shared.foursquareService {
                do {
                    return query.isEmpty ? try await service.searchNearby(location: searchCenter, limit: 30) : try await service.search(query: query, location: searchCenter, limit: 30)
                } catch {
                    print("Foursquare search failed: \(error)")
                }
            }
            return []
        }()
        
        async let mapKitTask: [EnrichmentData] = {
            if let service = Services.shared.mapKitService {
                do {
                    return query.isEmpty ? try await service.searchNearby(location: searchCenter, limit: 30) : try await service.search(query: query, location: searchCenter, limit: 30)
                } catch {
                    print("MapKit search failed: \(error)")
                }
            }
            return []
        }()
        
        let (fsqResults, mapResults) = await (fsqTask, mapKitTask)
        
        // 2. Merge and Deduplicate
        var merged: [EnrichmentData] = []
        var seenNames = Set<String>()
        
        // Helper to add if not a duplicate
        func addIfUnique(_ items: [EnrichmentData]) {
            for item in items {
                let name = item.title?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
                if name.isEmpty { continue }
                
                // Very basic deduplication: same name in the same area
                // In a production app, we'd check coordinates more precisely
                if seenNames.contains(name) { continue }
                
                seenNames.insert(name)
                merged.append(item)
            }
        }
        
        // Add current selection first to ensure it's at the top and unique
        if let selection = currentSelection {
            addIfUnique([selection])
        }
        
        // Add MapKit results (often contains better historical/landmark data)
        addIfUnique(mapResults)
        
        // Add Foursquare results (often contains more retail/food detail)
        addIfUnique(fsqResults)
        
        await MainActor.run {
            self.candidates = merged
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
            let oldName = item.placeContext?.name
            item.placeContext = newContext
            
            // Smart Title Update: If title matched old location or is generic, update it
            if let newName = newContext?.name {
                let current = item.title ?? ""
                let candidates = ["Home", "Unknown Place", "Current Location", oldName].compactMap { $0 }
                if current.isEmpty || candidates.contains(current) {
                    item.title = newName
                }
            }
            if let loc = newLocation {
                item.location = loc
            }
            item.categories = newCategories
            
            // 2. Persist
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
}
