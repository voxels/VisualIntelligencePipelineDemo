import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import MapKit

#if os(iOS)
import UIKit
#endif
import PhotosUI

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
    @State private var selectedPhotoItem: PhotosPickerItem? // Local state for picker
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
    
    private var uniquePinnedItems: [ProcessedItem] {
        var seen = Set<String>()
        return pinnedItems.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
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
                        ForEach(uniquePinnedItems) { item in
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
                                            Text(item.processingLog.last ?? "Processing...")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                                .lineLimit(1)
                                        } else if item.status == .reviewRequired {
                                            Text("Stalled - Review Required")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
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
                                    } else if item.status == .queued || item.status == .failed {
                                        Button {
                                            viewModel.processNow(item)
                                        } label: {
                                            Image(systemName: "flashlight.on.circle")
                                                .font(.title3)
                                                .foregroundStyle(.blue)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if item.status == .failed {
                                        viewModel.retryItem(item)
                                    } else {
                                        selection = item
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
                            Button {
                                Task { try? await pipelineService.processPendingQueue() }
                            } label: {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
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
                HStack {
                    // Use local state
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.body)
                    }

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
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let item = newItem, let data = try? await item.loadTransferable(type: Data.self) {
                     viewModel.importExternalImage(data: data)
                     selectedPhotoItem = nil // Reset picker
                }
            }
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
            let docs = detachedItems.filter { $0.entityType == "document" }
            let web = detachedItems.filter { $0.entityType == "page" || $0.entityType == "link" }
            let images = detachedItems.filter { $0.entityType == "image" || $0.entityType == "product" || $0.entityType == "media" }
            let other = detachedItems.filter { !["document", "page", "link", "image", "product", "media"].contains($0.entityType ?? "") }
            
            Section("Documents & Media") {
                if !docs.isEmpty {
                    DisclosureGroup("Documents") {
                        MasterChildGroupingView(items: docs, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                            .padding(.leading, 8)
                    }
                }
                if !web.isEmpty {
                    DisclosureGroup("Web Pages") {
                        MasterChildGroupingView(items: web, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                            .padding(.leading, 8)
                    }
                }
                if !images.isEmpty {
                    DisclosureGroup("Images") {
                         MasterChildGroupingView(items: images, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                            .padding(.leading, 8)
                    }
                }
                if !other.isEmpty {
                    DisclosureGroup("Other") {
                         MasterChildGroupingView(items: other, sharedWithYouManager: sharedWithYouManager, viewModel: viewModel, modelContext: modelContext)
                            .padding(.leading, 8)
                    }
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
    
    @Query private var metadata: [DiverSession]
    @State private var isExpanded = false
    
    init(sessionID: String, items: [ProcessedItem], viewModel: SidebarViewModel, modelContext: ModelContext, sharedWithYouManager: SharedWithYouManager) {
        self.sessionID = sessionID
        self.items = items
        self.viewModel = viewModel
        self.modelContext = modelContext
        self.sharedWithYouManager = sharedWithYouManager
        let id = sessionID
        self._metadata = Query(filter: #Predicate<DiverSession> { $0.sessionID == id })
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
        // Enforce uniqueness at the grouping level
        var seen = Set<String>()
        let uniqueItems = items.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
        
        let groups = Dictionary(grouping: uniqueItems) { $0.masterCaptureID ?? $0.id }
        
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
    @Bindable var session: DiverSession
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
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
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




// MARK: - EditLocationView







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

