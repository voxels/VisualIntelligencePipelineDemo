import SwiftUI
import SwiftData
import DiverKit
import DiverShared

#if os(iOS)
import UIKit
#endif

struct SidebarView: View {
    @Binding var selection: ProcessedItem?
    @StateObject private var viewModel = SidebarViewModel()
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager
    @Environment(\.modelContext) private var modelContext
    let pipelineService: MetadataPipelineService

    @State private var sharedExpanded = true
    @State private var processingExpanded = true
    @State private var libraryExpanded = true
    @State private var favoritesExpanded = true
    #if DEBUG
    @State private var developerExpanded = false
    #endif

    @EnvironmentObject private var navigationManager: NavigationManager
    
    // Fetch all items and filter in memory to avoid SwiftData predicate complexity with Enums
    @Query(sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]
    
    // Pinned Items
    @Query(filter: #Predicate<ProcessedItem> { $0.isFavorite == true }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var pinnedItems: [ProcessedItem]

    // Local Inputs (Fallback)
    @Query(sort: \LocalInput.createdAt, order: .reverse)
    private var inputs: [LocalInput]

    private var readyItems: [ProcessedItem] {
        let filtered = allItems.filter { $0.status == .ready }
        return viewModel.sortAndFilter(items: filtered)
    }

    private var activeItems: [ProcessedItem] {
        let filtered = allItems.filter { $0.status == .queued || $0.status == .processing || $0.status == .failed }
        return viewModel.sortAndFilter(items: filtered)
    }

    var body: some View {
        List(selection: $selection) {


            // Section 0.5: Daily Context
            if let dailyService = Services.shared.dailyContextService {
                DailyContextSection(service: dailyService)
            }
            
            // Section 0: Intelligence
            if IntelligenceCapability.isAvailable {
                Section("Intelligence") {
                    Button {
                        navigationManager.isScanActive = true
                    } label: {
                        Label("Scan for context", systemImage: "sparkles.tv")
                            .foregroundStyle(.cyan)
                    }

                    Button {
                        viewModel.showingShortcutGallery = true
                    } label: {
                        Label("Shortcuts & Automation", systemImage: "wand.and.stars")
                            .foregroundStyle(.purple)
                    }
                }
            }

            // Favorites Section (Dropdown)
            if !pinnedItems.isEmpty {
                 Section {
                     DisclosureGroup(isExpanded: $favoritesExpanded) {
                        ForEach(pinnedItems) { item in
                            NavigationLink(value: item) {
                                HStack {
                                    Label(title(for: item), systemImage: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    item.isFavorite = false
                                } label: {
                                    Label("Unfavorite", systemImage: "star.slash")
                                }
                            }
                        }
                     } label: {
                         Label("Favorites", systemImage: "star.square.fill")
                            .foregroundStyle(.yellow)
                     }
                 }
            }

            // Section 1: Shared with You
            if #available(iOS 16.0, macOS 13.0, *) {
                SharedWithYouView(manager: sharedWithYouManager)
            } else {
                SharedWithYouPlaceholder()
            }

            // Section 2: Active / Processing
            if !activeItems.isEmpty {
                Section {
                    if processingExpanded {
                        ForEach(activeItems) { item in
                            NavigationLink(value: item) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title(for: item))
                                            .font(.subheadline)
                                        if item.status == .failed {
                                            Text("Failed - Tap to retry")
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                        } else if item.status == .processing {
                                            Text("Processing...")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        } else {
                                            Text("Queued")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if item.status == .processing {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.deleteItem(item, context: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    viewModel.reprocessItem(item)
                                } label: {
                                    Label("Re-process", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                                
                                Button {
                                    viewModel.itemToEditLocation = item
                                } label: {
                                    Label("Edit Location", systemImage: "mappin.and.ellipse")
                                }
                                .tint(.purple)
                            }
                        }
                    }
                } header: {
                    DisclosureGroup(isExpanded: $processingExpanded) {
                    } label: {
                        HStack {
                            Label("Processing", systemImage: "gear.badge.questionmark")
                            Spacer()
                            if !activeItems.isEmpty {
                                Text("\(activeItems.count)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                    }
                }
            } else if !inputs.isEmpty && readyItems.isEmpty {
                // Fallback to showing inputs if no processed items exist yet
                Section {
                    if processingExpanded {
                        ForEach(inputs) { input in
                            Text(input.url ?? input.text ?? "Untitled")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    DisclosureGroup(isExpanded: $processingExpanded) {
                    } label: {
                        Label("Inbox", systemImage: "tray")
                    }
                }
            } else if readyItems.isEmpty {
                // Empty state when nothing is processing
                Section {
                    if processingExpanded {
                        ContentUnavailableView {
                            Label("All Caught Up", systemImage: "checkmark.circle.fill")
                        } description: {
                            Text("No items are currently being processed")
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    DisclosureGroup(isExpanded: $processingExpanded) {
                    } label: {
                        HStack {
                            Label("Processing", systemImage: "gear.badge.questionmark")
                            Spacer()
                            if !activeItems.isEmpty {
                                Text("\(activeItems.count)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                    }
                }
            }

            // Section 3: Library
            Section {
                if libraryExpanded {
                    if readyItems.isEmpty && activeItems.isEmpty && inputs.isEmpty {
                        ContentUnavailableView("Empty Library", systemImage: "books.vertical")
                    } else {
                        SessionContentView(items: readyItems, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                    }
                }
            } header: {
                DisclosureGroup(isExpanded: $libraryExpanded) {
                } label: {
                    Label("Library", systemImage: "books.vertical")
                }
            }

            // Section 4: Concepts
            Section("Memory") {
                NavigationLink {
                    ConceptListView()
                } label: {
                    Label("Concepts", systemImage: "brain.head.profile")
                        .foregroundStyle(.indigo)
                }
            }
            
            #if DEBUG
            // Section 5: Examples
            Section {
                if developerExpanded {
                    Button {
                        viewModel.importExamples(context: modelContext)
                    } label: {
                        HStack {
                            Label("Import Pipeline Examples", systemImage: "arrow.down.doc.fill")
                            if viewModel.isImporting {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                        .foregroundStyle(.orange)
                    }
                    .disabled(viewModel.isImporting)
                }
            } header: {
                DisclosureGroup(isExpanded: $developerExpanded) {
                } label: {
                    Label("Developer", systemImage: "hammer")
                }
            }
            #endif
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .sheet(item: $viewModel.itemToEditLocation) { item in
            EditLocationView(item: item)
        }
        .sheet(item: $viewModel.itemToReprocess) { item in
            ReprocessMetadataView(item: item)
        }
        .refreshable {
            await viewModel.refresh()
            if #available(iOS 16.0, macOS 13.0, *) {
                await sharedWithYouManager.processUnprocessedHighlights(modelContext: modelContext)
            }
        }
        .onAppear {
            viewModel.setPipelineService(pipelineService)
            let readyCount = readyItems.count
            let activeCount = activeItems.count
            let totalCount = allItems.count
            print("SidebarView appeared - Total: \(totalCount), Ready: \(readyCount), Active: \(activeCount), Inputs: \(inputs.count)")
        }
        .listStyle(.sidebar)
        .navigationTitle("Visual Intelligence")
        .searchable(text: $viewModel.searchText, prompt: "Search library")
        .environment(\.editMode, .constant(viewModel.isSelectionMode ? .active : .inactive))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.isSelectionMode {
                    Button("Cancel") {
                        withAnimation {
                            viewModel.isSelectionMode = false
                            viewModel.selectedSessions.removeAll()
                        }
                    }
                } else {
                    Button("Edit") {
                        withAnimation {
                            viewModel.isSelectionMode = true
                        }
                    }
                }
            }
            
            if viewModel.isSelectionMode && !viewModel.selectedSessions.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        viewModel.generateGroupSummary(context: modelContext)
                    } label: {
                        Text("Summarize (\(viewModel.selectedSessions.count))")
                            .bold()
                    }
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Sort By", selection: $viewModel.sortOrder) {
                        ForEach(SidebarViewModel.SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $viewModel.showingShortcutGallery) {
            ShortcutGalleryView()
        }
        .sheet(item: $viewModel.groupSummaryResult) { result in
            NavigationStack {
                ScrollView {
                    Text(result.text)
                        .padding()
                        .font(.body)
                }
                .navigationTitle("Session Group Summary")
                .toolbar {
                    Button("Done") {
                        viewModel.groupSummaryResult = nil
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        #endif
    }
    
    
    private func title(for item: ProcessedItem) -> String {
        return item.title ?? item.url ?? "Untitled"
    }
    
    private func formattedDate(for item: ProcessedItem) -> String {
        let date = item.lastProcessedAt ?? item.updatedAt
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Concept List View
struct ConceptListView: View {
    @Query(sort: \UserConcept.weight, order: .reverse) private var concepts: [UserConcept]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if concepts.isEmpty {
#if os(iOS)
                ContentUnavailableView(
                    "No Concepts",
                    systemImage: "brain.head.profile",
                    description: Text("Concepts extracted from your items will appear here.")
                )
#else
                Text("No Concepts")
#endif
            } else {
                ForEach(concepts) { concept in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(concept.name)
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1f", concept.weight))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if !concept.definition.isEmpty {
                            Text(concept.definition)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteConcepts)
            }
        }
        .navigationTitle("Concepts")
        #if os(macOS)
        .navigationSubtitle("\(concepts.count) items")
        #endif
    }

    private func deleteConcepts(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(concepts[index])
            }
            try? modelContext.save()
        }
    }
}

struct LibraryItemRow: View {
    let item: ProcessedItem
    let sharedWithYouManager: SharedWithYouManager
    let viewModel: SidebarViewModel
    let modelContext: ModelContext
    
    var body: some View {
        NavigationLink(value: item) {
            HStack(spacing: 12) {
                // Thumbnail
                if let data = item.rawPayload, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                } else if let snapshotPath = item.webContext?.snapshotURL {
                    AsyncImage(url: URL(fileURLWithPath: snapshotPath)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.1)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                } else {
                    // Fallback Icon
                    ZStack {
                        Color.secondary.opacity(0.1)
                        Image(systemName: item.entityType == "document" ? "doc.fill" : "safari")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: item))
                        .font(.headline)
                        .lineLimit(2)
                    if let url = item.url {
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Text(formattedDate(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Attribution View
                    if #available(iOS 16.0, macOS 13.0, *),
                       let attributionID = item.attributionID,
                       let highlight = sharedWithYouManager.findHighlight(id: attributionID) {
                        DiverAttributionView(highlight: highlight)
                            .frame(height: 30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
             Button {
                viewModel.reprocessItem(item)
            } label: {
                Label("Re-process", systemImage: "arrow.clockwise")
            }
            .tint(.orange)
            
            Button {
                viewModel.itemToEditLocation = item
            } label: {
                Label("Edit Location", systemImage: "mappin.and.ellipse")
            }
            .tint(.purple)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.deleteItem(item, context: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                viewModel.shareItem(item)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
    }
    
    private func title(for item: ProcessedItem) -> String {
        return item.title ?? item.url ?? "Untitled"
    }
    
    private func formattedDate(for item: ProcessedItem) -> String {
        let date = item.lastProcessedAt ?? item.updatedAt
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// SessionHeaderView replaced by SessionCardOrchestrator

struct SessionContentView: View {
    let items: [ProcessedItem]
    let sharedWithYouManager: SharedWithYouManager
    let viewModel: SidebarViewModel
    let modelContext: ModelContext
    
    var body: some View {
        // Grouping Logic: Session -> Master -> Child
        let sessionGroups = Dictionary(grouping: items) { $0.sessionID ?? "detached" }
        
        let allKeys = sessionGroups.keys
        let sessionKeys = allKeys.filter { $0 != "detached" }
        let detachedItems = sessionGroups["detached"] ?? []
        
        // 1. Render Sessions
        let sortedSessions = sessionKeys.sorted { key1, key2 in
            let date1 = sessionGroups[key1]?.map { $0.updatedAt }.max() ?? Date.distantPast
            let date2 = sessionGroups[key2]?.map { $0.updatedAt }.max() ?? Date.distantPast
            return date1 > date2
        }
        
        ForEach(sortedSessions, id: \.self) { sessionKey in
            if let sessionItems = sessionGroups[sessionKey] {
                // Initialize metadata query manually or pass it?
                // SessionCardView will need to query metadata internally or be passed it.
                // Since we can't easily query inside a Loop without a wrapper, we'll let SessionCardViewOrchestrator handle it?
                // Or better: Use the existing pattern where the View subcomponent queries.
                
                SessionCardOrchestrator(
                    sessionID: sessionKey,
                    items: sessionItems,
                    viewModel: viewModel,
                    modelContext: modelContext,
                    sharedWithYouManager: sharedWithYouManager
                )
                .padding(.bottom, 20)
                .listRowInsets(EdgeInsets()) // Remove default padding for card look
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        
        // 2. Render Detached Items (Documents/Links)
        if !detachedItems.isEmpty {
            Section {
                DisclosureGroup("Documents & Links") {
                    MasterChildGroupingView(items: detachedItems, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                        .padding(.leading, 8)
                }
            }
        }
    }
}

struct SessionCardOrchestrator: View {
    let sessionID: String
    let items: [ProcessedItem]
    let viewModel: SidebarViewModel
    let modelContext: ModelContext
    let sharedWithYouManager: SharedWithYouManager
    
    @Query private var metadata: [SessionMetadata]
    @State private var isExpanded = false
    
    init(sessionID: String, items: [ProcessedItem], viewModel: SidebarViewModel, modelContext: ModelContext, sharedWithYouManager: SharedWithYouManager) {
        self.sessionID = sessionID
        self.items = items
        self.viewModel = viewModel
        self.modelContext = modelContext
        self.sharedWithYouManager = sharedWithYouManager
        let id = sessionID
        self._metadata = Query(filter: #Predicate<SessionMetadata> { $0.sessionID == id })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SessionCardView(
                sessionID: sessionID,
                items: items,
                metadata: metadata.first,
                isExpanded: $isExpanded
            )
            .contextMenu {
                 Button {
                     // showingEditSheet = true // TODO: Need to lift state or handle edit
                     viewModel.itemToReprocess = items.first // Hacky substitute for now?
                     // Ideally we trigger Session Edit from ViewModel
                 } label: {
                     Label("Edit Session", systemImage: "pencil")
                 }
                 
                 Button {
                     viewModel.generateSessionSummary(sessionID: sessionID, context: modelContext)
                 } label: {
                     Label("Analyze Context", systemImage: "wand.and.stars")
                 }
                 
                 Button {
                     viewModel.reprocessSession(sessionID: sessionID, context: modelContext)
                 } label: {
                     Label("Reprocess Session", systemImage: "arrow.clockwise")
                 }
                 
                 Button {
                     viewModel.duplicateSession(sessionID: sessionID, context: modelContext)
                 } label: {
                     Label("Duplicate Session", systemImage: "doc.on.doc")
                 }
                 
                 Button(role: .destructive) {
                     for item in items {
                         modelContext.delete(item)
                     }
                     try? modelContext.save()
                 } label: {
                     Label("Delete Session", systemImage: "trash")
                 }
            }
            
            if isExpanded {
                MasterChildGroupingView(items: items, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                    .padding(.leading, 4)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
    }
}

struct MasterChildGroupingView: View {
    let items: [ProcessedItem]
    let sharedWithYouManager: SharedWithYouManager
    let viewModel: SidebarViewModel
    let modelContext: ModelContext
    
    var body: some View {
        let groups = Dictionary(grouping: items) { $0.masterCaptureID ?? $0.id }
        
        let sortedKeys = groups.keys.sorted { key1, key2 in
            let date1 = groups[key1]?.map { $0.updatedAt }.max() ?? Date.distantPast
            let date2 = groups[key2]?.map { $0.updatedAt }.max() ?? Date.distantPast
            return date1 > date2
        }
        
        ForEach(sortedKeys, id: \.self) { key in
            let groupItems = groups[key] ?? []
            if let parent = groupItems.first(where: { $0.id == key }) ?? groupItems.first {
                let children = groupItems.filter { $0.id != parent.id }
                
                if children.isEmpty {
                    LibraryItemRowWithActions(item: parent, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                } else {
                    DisclosureGroup {
                        ForEach(children) { child in
                            LibraryItemRowWithActions(item: child, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                                .padding(.leading, 24)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 2)
                                        .padding(.vertical, 4),
                                    alignment: .leading
                                )
                                .padding(.leading, 4)

                        }
                    } label: {
                        LibraryItemRowWithActions(item: parent, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                    }
                }
            }
        }
    }
}

// MARK: - Session Edit View
struct SessionEditView: View {
    @Bindable var session: SessionMetadata
    var logs: [String] = []
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showLocationMap = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: Binding(
                        get: { session.title ?? "" },
                        set: { session.title = $0.isEmpty ? nil : $0 }
                    ))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Location", text: Binding(
                            get: { session.locationName ?? "" },
                            set: { session.locationName = $0.isEmpty ? nil : $0 }
                        ))
                        
                        Button {
                            showLocationMap = true
                        } label: {
                            Label("Update via Map", systemImage: "map")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    TextField("Summary", text: Binding(
                        get: { session.summary ?? "" },
                        set: { session.summary = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
                
                Section("Metadata") {
                    if let placeID = session.placeID {
                        LabeledContent("Place ID", value: placeID)
                    }
                    if let lat = session.latitude, let lng = session.longitude {
                        LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", lat, lng))
                    }
                    LabeledContent("Created", value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                
                if !logs.isEmpty {
                    Section("Processing Log") {
                        ForEach(logs, id: \.self) { log in
                            Text(log)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave?()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showLocationMap) {
                EditSessionLocationView(session: session)
            }
            .navigationDestination(for: ProcessedItem.self) { item in
                 ReferenceDetailView(item: item)
            }
        }
    }
}

// MARK: - Helper Views

struct LibraryItemRowWithActions: View {
    let item: ProcessedItem
    let sharedWithYouManager: SharedWithYouManager
    let viewModel: SidebarViewModel
    let modelContext: ModelContext
    
    var body: some View {
        LibraryItemRow(item: item, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
            .contextMenu {
                Button {
                    viewModel.itemToEditLocation = item
                } label: {
                    Label("Edit Location", systemImage: "mappin.and.ellipse")
                }
                
                Button {
                    item.isFavorite.toggle()
                } label: {
                    Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    item.isFavorite.toggle()
                } label: {
                    Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
    }
}

import MapKit

struct EditLocationView: View {
    @Bindable var item: ProcessedItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var candidates: [EnrichmentData] = []
    @State private var isLoading = false
    @State private var selectedCandidate: EnrichmentData?
    @State private var region: MKCoordinateRegion
    @State private var searchText = ""
    @State private var hasZoomedToSession = false
    
    init(item: ProcessedItem) {
        self.item = item
        
        // Try parsing item location safely
        var initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to SF (Saner default than 0,0)
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        if let locString = item.location {
            let components = locString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count == 2,
               let lat = Double(components[0]),
               let lon = Double(components[1]) {
                initialRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            }
        }
        
        _region = State(initialValue: initialRegion)
    }
    

    
    // Helper to fetch session location if item location is missing or user prefers session context
    @Query private var sessions: [SessionMetadata]
    
    private var sessionLocation: CLLocationCoordinate2D? {
        if let sessionID = item.sessionID, let session = sessions.first(where: { $0.sessionID == sessionID }),
           let lat = session.latitude, let lon = session.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    var allAnnotations: [AnnotationItem] {
        var items: [AnnotationItem] = []
        
        // 1. Session / Original Location
        if let sl = sessionLocation {
            items.append(AnnotationItem(coordinate: sl, color: .purple))
        } else if region.center.latitude != 0 {
             // Fallback to item location or map center if valid
            items.append(AnnotationItem(coordinate: region.center, color: .purple))
        }
        
        // 2. Candidates
        for candidate in candidates {
            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                 // Highlight selected
                let isSelected = selectedCandidate?.placeContext?.placeID == candidate.placeContext?.placeID
                items.append(AnnotationItem(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), color: isSelected ? .green : .red))
            }
        }
        
        return items
    }

    var body: some View {
        NavigationStack {
             // ... (List content identical)
             List {
                Section {
                    Map(coordinateRegion: $region, interactionModes: .all, showsUserLocation: false, annotationItems: allAnnotations) { place in
                        MapMarker(coordinate: place.coordinate, tint: place.color)
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                }
                
                Section("Current Location") {
                   VStack(alignment: .leading) {
                        Text(item.placeContext?.name ?? "Unknown Place")
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
                }
                
                Section("Nearby Places (KnowMaps)") {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if candidates.isEmpty {
                        Text("No places found nearby.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.placeContext?.placeID) { candidate in
                            Button {
                                selectedCandidate = candidate
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
                // simple debounce
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchCandidates()
            }
        }
        .disabled(isUpdating)
        .overlay {
            if isUpdating {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView("Updating Context...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                }
            }
        }
        .onAppear {
            // Robustly checking precedence: Item > Session > Default
            if let locString = item.location {
                 let components = locString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                 if components.count == 2,
                    let lat = Double(components[0]),
                    let lon = Double(components[1]) {
                     // Only update if not already set by user interaction (checking default span)
                     if region.span.latitudeDelta > 0.1 || !hasZoomedToSession {
                         region = MKCoordinateRegion(
                             center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                             span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                         )
                         hasZoomedToSession = true
                     }
                     return
                 }
            }
            
            if let sl = sessionLocation {
                 region = MKCoordinateRegion(
                    center: sl,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
                hasZoomedToSession = true
            }
        }
        .onChange(of: sessions) { _ in
            if !hasZoomedToSession, let sl = sessionLocation {
                 region = MKCoordinateRegion(
                    center: sl,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
                hasZoomedToSession = true
            }
        }
    }
    

    @State private var isUpdating = false
    
    private func fetchCandidates() async {
        guard let service = Services.shared.foursquareService else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Prioritize session location for search
        let searchCenter = sessionLocation ?? region.center
        if searchCenter.latitude == 0 && searchCenter.longitude == 0 { return }
        
        do {
            let results: [EnrichmentData]
            if searchText.isEmpty {
                 results = try await service.searchNearby(location: searchCenter, limit: 50)
            } else {
                 results = try await service.search(query: searchText, location: searchCenter, limit: 50)
            }
            
            await MainActor.run {
                self.candidates = results
            }
        } catch {
            print("❌ Failed to fetch candidates: \(error)")
        }
    }
    
    private func updateLocation() async {
        guard let candidate = selectedCandidate else { return }
        guard let contextService = Services.shared.contextQuestionService else { return }
        
        isUpdating = true
        defer { isUpdating = false }
        
        do {
            let (summary, _, purpose, tags) = try await contextService.processContext(from: candidate)
            
            await MainActor.run {
                // Update Session Metadata
                if let sessionID = item.sessionID,
                   let session = sessions.first(where: { $0.sessionID == sessionID }) {
                    session.locationName = candidate.placeContext?.name
                    session.placeID = candidate.placeContext?.placeID
                    if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                        session.latitude = lat
                        session.longitude = lon
                    }
                    
                    // Update all siblings in this session
                    // We need to fetch them
                    let descriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sessionID })
                    if let siblings = try? item.modelContext?.fetch(descriptor) {
                        for sibling in siblings {
                            sibling.placeContext = candidate.placeContext
                            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                                sibling.location = "\(lat),\(lon)"
                            }
                            sibling.categories = candidate.categories
                            let newTags = Set(candidate.styleTags + tags + sibling.tags)
                            sibling.tags = Array(newTags).sorted()
                            
                            if let purpose = purpose, !sibling.purposes.contains(purpose) {
                                sibling.purposes.append(purpose)
                            }
                        }
                    }
                } else {
                    // Fallback: If not in a session, just update the single item
                    item.placeContext = candidate.placeContext
                    if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                        item.location = "\(lat),\(lon)"
                    }
                    item.categories = candidate.categories
                    let newTags = Set(candidate.styleTags + tags)
                    item.tags = Array(newTags).sorted()
                    if let purpose = purpose {
                        item.purposes = [purpose]
                    }
                    if let summary = summary {
                        item.summary = summary
                    }
                }
                
                try? item.modelContext?.save()
                dismiss()
            }
        } catch {
            print("❌ Failed to regenerate context: \(error)")
            await MainActor.run {
                // Fallback update on error (just location info)
                 if let sessionID = item.sessionID,
                   let session = sessions.first(where: { $0.sessionID == sessionID }) {
                     session.locationName = candidate.placeContext?.name
                     session.placeID = candidate.placeContext?.placeID
                 }
                 
                item.placeContext = candidate.placeContext
                if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                    item.location = "\(lat),\(lon)"
                }
                try? item.modelContext?.save()
                dismiss()
            }
        }
    }
}
// MARK: - EditSessionLocationView
struct EditSessionLocationView: View {
    @Bindable var session: SessionMetadata
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var candidates: [EnrichmentData] = []
    @State private var isLoading = false
    @State private var selectedCandidate: EnrichmentData?
    @State private var region: MKCoordinateRegion
    @State private var searchText = ""
    @State private var isUpdating = false
    
    init(session: SessionMetadata) {
        self.session = session
        
        if let lat = session.latitude, let lon = session.longitude {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        } else {
             _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100)
            ))
        }
    }
    
    var allAnnotations: [AnnotationItem] {
        var items: [AnnotationItem] = []
        if region.center.latitude != 0 {
            items.append(AnnotationItem(coordinate: region.center, color: .purple))
        }
        for candidate in candidates {
            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                let isSelected = selectedCandidate?.placeContext?.placeID == candidate.placeContext?.placeID
                items.append(AnnotationItem(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), color: isSelected ? .green : .red))
            }
        }
        return items
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map(coordinateRegion: $region, interactionModes: .all, showsUserLocation: false, annotationItems: allAnnotations) { place in
                        MapMarker(coordinate: place.coordinate, tint: place.color)
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
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
                
                Section("Nearby Places (KnowMaps)") {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if candidates.isEmpty {
                        Text("No places found nearby.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.placeContext?.placeID) { candidate in
                            Button {
                                selectedCandidate = candidate
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
            .navigationTitle("Edit Session Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        Task { await updateLocation() }
                    }
                    .disabled(selectedCandidate == nil || isUpdating)
                }
            }
            .task(id: searchText) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchCandidates()
            }
        }
        .disabled(isUpdating)
    }
    
    private func fetchCandidates() async {
        guard let service = Services.shared.foursquareService else { return }
        isLoading = true
        defer { isLoading = false }
        
        let searchCenter = region.center
        if searchCenter.latitude == 0 && searchCenter.longitude == 0 { return }
        
        do {
            let results: [EnrichmentData]
            if searchText.isEmpty {
                 results = try await service.searchNearby(location: searchCenter, limit: 50)
            } else {
                 results = try await service.search(query: searchText, location: searchCenter, limit: 50)
            }
            await MainActor.run { self.candidates = results }
        } catch {
            print("❌ Failed to fetch candidates: \(error)")
        }
    }
    
    private func updateLocation() async {
        guard let candidate = selectedCandidate else { return }
        isUpdating = true
        defer { isUpdating = false }
        
        await MainActor.run {
            session.locationName = candidate.placeContext?.name
            session.placeID = candidate.placeContext?.placeID
            if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                session.latitude = lat
                session.longitude = lon
            }
            
            // Propagate to all children
            let targetID = session.sessionID
            let descriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == targetID })
            if let items = try? modelContext.fetch(descriptor) {
                for item in items {
                    item.placeContext = candidate.placeContext
                    if let lat = candidate.placeContext?.latitude, let lon = candidate.placeContext?.longitude {
                        item.location = "\(lat),\(lon)"
                    }
                    // Simple merge of categories/tags
                    item.categories = candidate.categories
                }
            }
            
            try? modelContext.save()
            dismiss()
        }
    }
}


struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

struct ReprocessMetadataView: View {
    let item: ProcessedItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var sessionTitle: String = ""
    @State private var sessionSummary: String = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session Metadata") {
                    if let image = itemImage {
                        #if os(iOS)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                            .clipped()
                        #endif
                    }
                    
                    TextField("Session Title", text: $sessionTitle)
                    
                    if !sessionSummary.isEmpty {
                        Text(sessionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Location Context") {
                    if let place = item.placeContext?.name {
                        LabeledContent("Place", value: place)
                    }
                    if let loc = item.location {
                        LabeledContent("Coordinates", value: loc)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        
                        Text(item.sessionID ?? "No Session ID")
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                
                Section {
                    Button {
                        startReprocessing()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else if item.rawPayload == nil {
                            Text("Original Image Missing")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Confirm & Reprocess")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(item.rawPayload == nil || isLoading)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Reprocess Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                sessionTitle = item.title ?? "Untitled Session"
                sessionSummary = item.summary ?? ""
            }
        }
    }
    
    private var itemImage: UIImage? {
        if let data = item.rawPayload {
            return UIImage(data: data)
        }
        return nil
    }
    
    private func startReprocessing() {
        guard let imageData = item.rawPayload else { return }
        
        isLoading = true
        
        // 1. Set Shared Context - New Session
        let newSessionID = UUID().uuidString
        
        let context = ReprocessContext(
            imageData: imageData,
            sessionID: newSessionID,
            location: item.location,
            placeID: item.placeContext?.placeID,
            placeName: item.placeContext?.name
        )
        
        Task { @MainActor in
            Services.shared.pendingReprocessContext = context
            
            // 2. Dismiss this sheet
            dismiss()
            
            // 3. Trigger Visual Intelligence
            try? await Task.sleep(nanoseconds: 300_000_000)
            NotificationCenter.default.post(name: .openVisualIntelligence, object: nil)
        }
    }
}

// MARK: - SessionCardView (Moved from separate file for target inclusion)

struct SessionCardView: View {
    let sessionID: String
    let items: [ProcessedItem]
    let metadata: SessionMetadata?
    @Binding var isExpanded: Bool
    
    // Derived properties
    private var heroImage: UIImage? {
        // Find best quality image (e.g. from rawPayload or web snapshot)
        // Prefer first item in list for consistency
        for item in items {
            if let data = item.rawPayload, let image = UIImage(data: data) {
                return image
            }
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
    
    private var title: String {
        metadata?.title ?? items.first?.title ?? "Untitled Session"
    }
    
    private var subtitle: String {
        // Location + Date or just Date
        var components: [String] = []
        if let loc = metadata?.locationName {
            components.append(loc)
        }
        if let date = items.first?.createdAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            components.append(formatter.string(from: date))
        }
        return components.isEmpty ? "Unknown Date" : components.joined(separator: " • ")
    }
    
    private var summary: String? {
        metadata?.summary
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image Area
            if let image = heroImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding()
                    }
            } else {
                // Fallback Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
            }
            
            // Tertiary Context / LLM Summary
            if let summary = summary {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                .padding(.bottom, isExpanded ? 8 : 12)
                .padding(.top, 8)
            }
            
            // Dropdown Chevron Area (Tap to expand)
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide items" : "Show \(items.count) items")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.blue)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemBackground))
            }
            .buttonStyle(.plain)
             
            // Divider if not expanded, or if expanded content follows in SidebarView
             if !isExpanded {
                 Divider()
             }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 4) // Slight inset from list edges
        .padding(.vertical, 6)
    }
    }
}

// MARK: - Daily Context Section
struct DailyContextSection: View {
    @ObservedObject var service: DailyContextService
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if service.isGenerating {
                    HStack {
                        Text("Summarizing day...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                } else {
                    Text(service.dailySummary)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .italic()
                        .padding(.vertical, 4)
                        .transition(.opacity)
                }
            }
        } header: {
            HStack {
                Label("Today's Narrative", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button {
                    Task { await service.updateSummary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
        }
    }
}
