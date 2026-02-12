//
//  SidebarView.swift
//  VisualIntelligencePipeline
//
//  Clean hierarchical sidebar with proper selection handling.
//  Structure: Collections → Sessions → Items
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import MapKit

#if os(iOS)
import UIKit
#endif
import PhotosUI
import Photos

// MARK: - Main Sidebar View

struct SidebarView: View {
    @Binding var selectedSession: DiverSession?
    @StateObject private var viewModel = SidebarViewModel()
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager
    @EnvironmentObject private var navigationManager: NavigationManager
    @Environment(\.modelContext) private var modelContext
    let pipelineService: MetadataPipelineService
    
    // MARK: - State
    @State private var collectionsExpanded = true
    @State private var sessionsExpanded = true
    @State private var processingExpanded = true
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    // Collection Management State
    @State private var sessionToAddToCollection: DiverSession?
    @State private var showingCreateCollection = false
    @State private var sessionForNewCollection: DiverSession?
    @State private var sessionForLocationEdit: DiverSession?
    @State private var newCollectionName = ""
    
    // Collection Renaming State
    @State private var collectionToRename: DiverCollection?
    
    // Session Renaming State
    @State private var sessionToRename: DiverSession?
    @State private var newSessionTitle = ""
    
    // MARK: - Queries
    @Query(sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]
    
    @Query(filter: #Predicate<ProcessedItem> { $0.isFavorite == true }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var favoriteItems: [ProcessedItem]
    
    @Query(sort: \DiverCollection.updatedAt, order: .reverse)
    private var collections: [DiverCollection]
    
    @Query(sort: \DiverSession.updatedAt, order: .reverse)
    private var sessions: [DiverSession]
    
    @Query(filter: #Predicate<DiverSession> { $0.isFavorite == true }, sort: \DiverSession.updatedAt, order: .reverse)
    private var favoriteSessions: [DiverSession]
    
    @Query(sort: \UserConcept.weight, order: .reverse)
    private var allConcepts: [UserConcept]
    
    // MARK: - Computed Properties
    
    private var readyItems: [ProcessedItem] {
        allItems.filter { $0.status == .ready }
    }
    
    private var processingItems: [ProcessedItem] {
        allItems.filter { $0.status == .queued || $0.status == .processing }
    }
    
    /// Session IDs that belong to any collection
    private var collectionSessionIDs: Set<String> {
        Set(collections.flatMap { $0.sessionIDs })
    }
    
    /// Sessions not in any collection
    private var standaloneSessions: [DiverSession] {
        sessions.filter { !collectionSessionIDs.contains($0.sessionID) }
    }
    
    /// Items with no sessionID
    private var uncategorizedItems: [ProcessedItem] {
        readyItems.filter { $0.sessionID == nil }
    }
    
    
    // MARK: - Library Sorting
    
    private enum LibraryItem: Identifiable {
        case collection(DiverCollection)
        case session(DiverSession)
        
        var id: String {
            switch self {
            case .collection(let c): return c.collectionID
            case .session(let s): return s.sessionID
            }
        }
        
        var updatedAt: Date {
            switch self {
            case .collection(let c): return c.updatedAt
            case .session(let s): return s.updatedAt
            }
        }
    }
    
    private var libraryItems: [LibraryItem] {
        let collectionItems = collections.map { LibraryItem.collection($0) }
        let sessionItems = standaloneSessions.map { LibraryItem.session($0) }
        return (collectionItems + sessionItems).sorted { $0.updatedAt > $1.updatedAt }
    }
    
    // MARK: - Body
    
    var body: some View {
        List(selection: $selectedSession) {
            // Intelligence Actions
            intelligenceSection
            
            // Daily Summary
            if ContextQuestionService.isAvailable, let service = Services.shared.dailyContextService {
                DailySummaryCard(service: service)
            }
            
            // Collections with Sessions
            favoritesSection
            librarySection
            
            // Shared with You
            if #available(iOS 16.0, *) {
                SharedWithYouView(manager: sharedWithYouManager)
            }
                        
            // Inbox (Uncategorized Items)
            if !uncategorizedItems.isEmpty {
                inboxSection
            }
                        
            // Processing Items - moved above Memory/Today
            if !processingItems.isEmpty {
                processingSection
            }
            
            // Memory/Concepts
            memorySection
            
            #if DEBUG || DEBUG_MEMORY
            // Debug Info
            Section("Info") {
                Text("Total Items: \(allItems.count)")
                Text("Uncategorized: \(uncategorizedItems.count)")
                Text("Sessions: \(sessions.count)")
            }
            #endif
        }
        .listStyle(.sidebar)
        .navigationTitle("Visual Intelligence")
        .searchable(text: $viewModel.searchText, prompt: "Search items...")
        .refreshable {
            await viewModel.refresh()
            if #available(iOS 16.0, macOS 13.0, *) {
                sharedWithYouManager.refreshHighlights()
            }
        }
        .onAppear {
            viewModel.setPipelineService(pipelineService)
        }
        .sheet(item: $viewModel.itemToEditLocation) { item in
            EditLocationView(item: item)
        }
        .sheet(item: $viewModel.itemToReprocess) { item in
            ReprocessMetadataView(item: item)
        }
        .sheet(item: $sessionForLocationEdit) { session in
            EditSessionLocationView(session: session)
        }
        .overlay(alignment: .bottom) {
            if viewModel.isMaintaining {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.maintenanceProgress)
                        .progressViewStyle(.linear)
                    Text("Rebuilding Library (\(Int(viewModel.maintenanceProgress * 100))%)...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .shadow(radius: 2)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        navigationManager.scanSessionID = nil // Start fresh
                        navigationManager.isScanActive = true
                    } label: {
                        Label("Create New Context", systemImage: "sparkles.tv")
                    }
                    
                    Divider()
                    
                    Button {
                        viewModel.isImporting = true
                    } label: {
                        Label("Import from Photos", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        viewModel.showingShortcutGallery = true
                    } label: {
                        Label("Shortcuts", systemImage: "square.on.square")
                    }
                    
                    Divider()
                    
                    
                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingShortcutGallery) {
            ShortcutGalleryView()
        }
        .photosPicker(
            isPresented: $viewModel.isImporting,
            selection: $selectedPhotos,
            maxSelectionCount: 20,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotos) { oldValue, newValue in
            guard !newValue.isEmpty else { return }
            let target = viewModel.importTargetSession
            Task {
                await viewModel.importSelectedPhotos(newValue, context: modelContext, targetSession: target)
                selectedPhotos = []
                
                // Reset target session on main actor
                await MainActor.run {
                    viewModel.importTargetSession = nil
                }
            }
        }
        .alert("Create New Collection", isPresented: $showingCreateCollection) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {
                sessionForNewCollection = nil
                newCollectionName = ""
            }
            Button("Create") {
                if let session = sessionForNewCollection, !newCollectionName.isEmpty {
                    viewModel.createCollection(name: newCollectionName, session: session, context: modelContext)
                }
                sessionForNewCollection = nil
                newCollectionName = ""
            }
        } message: {
            Text("Enter a name for the new collection")
        }
        .alert("Rename Collection", isPresented: Binding(
            get: { collectionToRename != nil },
            set: { if !$0 { collectionToRename = nil } }
        )) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {
                collectionToRename = nil
                newCollectionName = ""
            }
            Button("Save") {
                if let collection = collectionToRename, !newCollectionName.isEmpty {
                    viewModel.renameCollection(collection, name: newCollectionName, context: modelContext)
                }
                collectionToRename = nil
                newCollectionName = ""
            }
        } message: {
            Text("Enter a new name for this collection")
        }
        .alert("Rename Session", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Session Title", text: $newSessionTitle)
            Button("Cancel", role: .cancel) {
                sessionToRename = nil
                newSessionTitle = ""
            }
            Button("Save") {
                if let session = sessionToRename, !newSessionTitle.isEmpty {
                    viewModel.renameSession(session, title: newSessionTitle, context: modelContext)
                }
                sessionToRename = nil
                newSessionTitle = ""
            }
        } message: {
            Text("Enter a new title for this session")
        }
    }
    
    @ViewBuilder
    private var favoritesSection: some View {
        if !favoriteItems.isEmpty || !favoriteSessions.isEmpty {
            Section("Favorites") {
                // Favorite Sessions
                ForEach(favoriteSessions) { session in
                    NavigationLink(value: session) {
                        Label {
                            Text(session.displayTitle)
                        } icon: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .contextMenu {
                        Button {
                            viewModel.toggleFavorite(for: session, context: modelContext)
                        } label: {
                            Label("Unfavorite", systemImage: "star.slash")
                        }
                    }
                }
                
                // Favorite Items
                ForEach(favoriteItems) { item in
                    Button {
                        // Find parent session
                        if let sessionID = item.sessionID {
                            if let session = sessions.first(where: { $0.sessionID == sessionID }) {
                                selectedSession = session
                                navigationManager.selectedSession = session
                            }
                        }
                        // Select the item itself
                        navigationManager.selection = item
                    } label: {
                        ItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let sessionID = item.sessionID, let session = sessions.first(where: { $0.sessionID == sessionID }) {
                            Button {
                                viewModel.setSessionAsCurrent(session, context: modelContext)
                            } label: {
                                Label("Set session as Current", systemImage: "clock.arrow.2.circlepath")
                            }
                            Divider()
                        }
                        
                        Button {
                            viewModel.toggleFavorite(for: item, context: modelContext)
                        } label: {
                            Label(item.isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: item.isFavorite ? "star.slash" : "star.fill")
                        }
                    }
                }
            }
        }
    }
    
    
    // MARK: - Sections
    
    @ViewBuilder
    private var librarySection: some View {
        Section("Library") {
            // Unified Sorted Library
            ForEach(libraryItems) { item in
                switch item {
                case .collection(let collection):
                    collectionGroup(for: collection)
                case .session(let session):
                    standaloneSessionRow(for: session)
                }
            }
            
            // Delete selected button
            if viewModel.isSelectionMode && !viewModel.selectedSessions.isEmpty {
                Button(role: .destructive) {
                    viewModel.deleteSelectedSessions(context: modelContext)
                } label: {
                    Label("Delete \(viewModel.selectedSessions.count) Selected", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .dropDestination(for: SessionTransfer.self) { transfers, location in
            guard let transfer = transfers.first else { return false }
            // Remove from ANY collection (move to root) when dropped on the general library area
            Task { @MainActor in
                viewModel.removeSessionFromCollection(sessionID: transfer.id, context: modelContext)
            }
            return true
        }
        .dropDestination(for: ItemTransfer.self) { transfers, location in
            guard let transfer = transfers.first else { return false }
            // Create a NEW standalone session with this item
            Task { @MainActor in
                viewModel.createStandaloneSessionWithItem(itemID: transfer.id, context: modelContext)
            }
            return true
        }
    }
    
    struct SidebarSessionRow: View {
        let session: DiverSession
        @ObservedObject var viewModel: SidebarViewModel
        let allItems: [ProcessedItem]
        let allConcepts: [UserConcept]
        
        let onLocationEdit: (DiverSession) -> Void
        let onRename: (DiverSession, String) -> Void
        let onNewCollection: (DiverSession, String) -> Void
        let onAddSession: (DiverSession, DiverCollection) -> Void
        let collections: [DiverCollection]
        let analyzeSession: (DiverSession) -> Void
        
        @Environment(\.modelContext) private var modelContext
        
        var body: some View {
            if viewModel.isSelectionMode {
                selectionRow
                    .contextMenu {
                        contextMenuContent
                    }
            } else {
                NavigationLink(value: session) {
                    SessionRowLabel(session: session, allItems: allItems)
                }
                .contextMenu {
                    contextMenuContent
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteSession(session, context: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Button {
                        onRename(session, session.displayTitle)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        viewModel.setSessionAsCurrent(session, context: modelContext)
                    } label: {
                        Label("Set Current", systemImage: "clock.arrow.2.circlepath")
                    }
                    .tint(.orange)
                }
                .draggable(SessionTransfer(id: session.sessionID))
                .dropDestination(for: ItemTransfer.self) { items, location in
                    // Allow dropping items into sessions inside collections
                    viewModel.moveItems(items, to: session, context: modelContext)
                    return true
                } isTargeted: { targeted in
                    isTargeted = targeted
                }
                .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(8)
            }
        }
        
        @State private var isTargeted = false
        
        private var selectionRow: some View {
            Button {
                if viewModel.selectedSessions.contains(session.sessionID) {
                    viewModel.selectedSessions.remove(session.sessionID)
                } else {
                    viewModel.selectedSessions.insert(session.sessionID)
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.selectedSessions.contains(session.sessionID) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.selectedSessions.contains(session.sessionID) ? .blue : .secondary)
                    SessionRowLabel(session: session, allItems: allItems)
                }
            }
            .buttonStyle(.plain)
        }
        
        @ViewBuilder
        private var contextMenuContent: some View {
            // Set as Current (Priority Action)
            Button {
                viewModel.setSessionAsCurrent(session, context: modelContext)
            } label: {
                Label("Set as Current", systemImage: "clock.arrow.2.circlepath")
            }
            
            Divider()
            
            // Add to existing collection
            if !collections.isEmpty {
                Menu {
                    ForEach(collections) { collection in
                        Button {
                            onAddSession(session, collection)
                        } label: {
                            Label(collection.name, systemImage: "folder.fill")
                        }
                    }
                } label: {
                    Label("Add to Collection", systemImage: "folder.badge.plus")
                }
            }
            
            // Create new collection from session
            Button {
                onNewCollection(session, session.displayTitle)
            } label: {
                Label("Create New Collection", systemImage: "folder.fill.badge.plus")
            }
            
            Button {
                // Set target session and open picker
                viewModel.importTargetSession = session
                viewModel.isImporting = true
            } label: {
                Label("Import Photos to Session", systemImage: "photo.badge.plus")
            }
            
            Button {
                onLocationEdit(session)
            } label: {
                Label("Edit Location", systemImage: "mappin.and.ellipse")
            }
            
            Button {
                onRename(session, session.displayTitle)
            } label: {
                Label("Rename Session", systemImage: "pencil")
            }
            
            Button {
                analyzeSession(session)
            } label: {
                Label("Analyze Session", systemImage: "sparkles")
            }
            
            Divider()
            
            Button(role: .destructive) {
                viewModel.deleteSession(session, context: modelContext)
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
    }
    
    private func analyzeSession(_ session: DiverSession) {
        Task {
            let localPipeline = LocalPipelineService(modelContext: modelContext)
            await localPipeline.generateAndSaveSessionSummary(sessionID: session.sessionID)
            print("✅ Triggered analysis for session: \(session.title ?? session.sessionID)")
        }
    }
    
    @ViewBuilder
    private var intelligenceSection: some View {
        Section("Current Context") {
                if let lastSession = sessions.first {
                    // Full contextual summary
                    if ContextQuestionService.isAvailable, let summary = lastSession.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    
                    // Related concepts chips
                    if ContextQuestionService.isAvailable {
                        let concepts = viewModel.relatedConcepts(for: lastSession, allItems: allItems, allConcepts: allConcepts)
                        if !concepts.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(concepts) { concept in
                                        Text(concept.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.purple)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(.purple.opacity(0.1))
                                            )
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(.purple.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    Button {
                        navigationManager.scanSessionID = lastSession.sessionID
                        navigationManager.isScanActive = true
                    } label: {
                        HStack(spacing: 12) {
                            // Thumbnail Preview
                            if let preview = previewImage(for: lastSession) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                    )
                            } else {
                                Image(systemName: "plus.viewfinder")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(.cyan.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.cyan)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Image")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                
                                if let location = lastSession.locationName {
                                    Text(location)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text(lastSession.title ?? "Current Session")
                                        .font(.caption2)
                                    .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.importTargetSession = lastSession
                            viewModel.isImporting = true
                        } label: {
                            Label("Import from Photos", systemImage: "photo")
                        }
                    }
                    
                    // New Note button - creates empty document for this session
                    Button {
                        let newNote = viewModel.createNewNoteForSession(lastSession, context: modelContext)
                        // Ensure we navigate hierarchy: Session -> Item
                        // 1. Select the session (Pushes Content Pane on iPhone)
                        navigationManager.selectedSession = lastSession
                        // 2. Select the item (Pushes Detail Pane)
                        navigationManager.selection = newNote
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(.purple.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.purple)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Note")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                
                                Text("Add text to context")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        navigationManager.scanSessionID = nil // Start fresh
                        navigationManager.isScanActive = true
                    } label: {
                        Label("Scan for Context", systemImage: "sparkles.tv")
                            .foregroundStyle(.cyan)
                    }
                }
            }
        }
    
    private func previewImage(for session: DiverSession) -> UIImage? {
        viewModel.previewImage(for: session, allItems: allItems)
    }
    
    @ViewBuilder
    private var inboxSection: some View {
        Section("Inbox") {
            ForEach(uncategorizedItems) { item in
                Button {
                    // Navigate to item
                    navigationManager.selection = item
                } label: {
                    ItemRow(item: item)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteItem(item, context: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        viewModel.toggleFavorite(for: item, context: modelContext)
                    } label: {
                        Label(item.isFavorite ? "Unfavorite" : "Favorite",
                              systemImage: item.isFavorite ? "star.slash" : "star.fill")
                    }
                    
                    if !collections.isEmpty {
                        Menu {
                            ForEach(collections) { collection in
                                Button {
                                    // Move item to a new session in this collection?
                                    // Or just assign to collection (not supported directly on item)
                                    // Best: Create new session in collection with this item
                                    viewModel.createSessionWithItem(item, in: collection, context: modelContext)
                                } label: {
                                    Label(collection.name, systemImage: "folder")
                                }
                            }
                        } label: {
                            Label("Move to Collection", systemImage: "folder.badge.plus")
                        }
                    }
                }
                .draggable(ItemTransfer(id: item.id))
            }
        }
    }
    
    @ViewBuilder
    private var processingSection: some View {
        Section {
            DisclosureGroup(isExpanded: $processingExpanded) {
                ForEach(processingItems) { item in
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title ?? item.url ?? "Processing...")
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            // Status subtitle from processing log or status
                            if let lastLog = item.processingLog.last {
                                // Extract just the message part after the date
                                let message = lastLog.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
                                Text(message.isEmpty ? item.status.rawValue.capitalized : message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(item.status.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            viewModel.processNow(item)
                        } label: {
                            Label("Process Now", systemImage: "bolt.fill")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.cancelProcessing(item, context: modelContext)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }
                }
            } label: {
                Label("Processing (\(processingItems.count))", systemImage: "gear")
                    .foregroundStyle(.orange)
            }
        }
    }
    
    /// Process an item immediately with high priority
    
    
    
    @ViewBuilder
    private var memorySection: some View {
        Section("Memory") {
            NavigationLink {
                ConceptListView()
            } label: {
                Label("Concepts", systemImage: "brain.head.profile")
                    .foregroundStyle(.purple)
            }
        }
    }
    
}

// MARK: - Session Row Label (for 3-pane navigation)

struct SessionRowLabel: View {
    let session: DiverSession
    let allItems: [ProcessedItem]
    
    private var sessionTitle: String {
        if let title = session.title, !title.isEmpty {
            return title
        }
        
        // Try to use a top concept from session items as fallback
        let topConcept = sessionItems
            .flatMap { $0.categories + $0.tags }
            .reduce(into: [:]) { counts, concept in counts[concept, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key
        
        if let concept = topConcept, !concept.isEmpty {
            return concept.capitalized
        }
        
        if let location = session.locationName, !location.isEmpty {
            return location
        }
        return "Session"
    }
    
    private var subtitle: String {
        var components: [String] = []
        if let loc = session.locationName, !loc.isEmpty, session.title != nil {
            // Only show location in subtitle if we have a title (otherwise it's the title)
            components.append(loc)
        }
        
        // Add dominant activity/purpose if available
        let purposes = sessionItems.flatMap { $0.purposes }.filter { !$0.isEmpty }
        if let topPurpose = purposes.reduce(into: [:], { counts, purpose in counts[purpose, default: 0] += 1 })
            .max(by: { $0.value < $1.value })?.key {
            components.append(topPurpose)
        }
        
        components.append(session.createdAt.formatted(date: .abbreviated, time: .shortened))
        return components.joined(separator: " • ")
    }
    
    private var sessionItems: [ProcessedItem] {
        allItems.filter { $0.sessionID == session.sessionID && $0.status == .ready }
    }
    
    private var heroImage: UIImage? {
        for item in sessionItems {
            if let data = item.rawPayload, let image = UIImage(data: data) {
                return image
            }
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
    
    private var fallbackConfig: ItemIconConfig {
        // Check for dominant purpose to determine icon (e.g. Activity)
        let purposes = sessionItems.flatMap { $0.purposes }
        if !purposes.isEmpty {
            return ItemIconConfig(iconName: "figure.run", color: .orange)
        }
        
        if let first = sessionItems.first {
            return ItemIconConfig.forItem(first)
        }
        return ItemIconConfig(iconName: "photo.stack", color: .secondary)
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Hero Image with overlay text
            if let image = heroImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(minWidth: 0, maxWidth: 280, minHeight: 0, maxHeight: 280)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sessionTitle)
                                .font(.headline)
                                .bold()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(8)
                    }
                    .cornerRadius(8)
            } else {
                // Fallback: Icon + Text layout
                HStack(spacing: 10) {
                    let config = fallbackConfig
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(config.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: config.iconName)
                                .foregroundStyle(config.color)
                                .font(.title3)
                        }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionTitle)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            
            // LLM Session Summary
            if ContextQuestionService.isAvailable, let summary = session.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
            } else if ContextQuestionService.isAvailable {
                Text("No Summary Available")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5)) // Made less prominent
                    .padding(.top, 4)
            }
        }
        .padding(4)
    }
}


// MARK: - Item Row

struct ItemRow: View {
    let item: ProcessedItem
    
    private var displayTitle: String {
        item.displayTitle
    }
    
    private var formattedDate: String {
        item.relativeUpdatedDate
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                if ContextQuestionService.isAvailable {
                    HStack(spacing: 4) {
                        if let entityType = item.entityType {
                            if entityType.lowercased() == "activity", let purpose = item.purposes.first {
                                Text(purpose)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(entityType.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(formattedDate)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        ThumbnailView(item: item, size: 36, cornerRadius: 6)
    }
}

// MARK: - Item Row With Actions

struct ItemRowWithActions: View {
    let item: ProcessedItem
    let onDelete: () -> Void
    let onReprocess: () -> Void
    
    var body: some View {
        ItemRow(item: item)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    onReprocess()
                } label: {
                    Label("Reprocess", systemImage: "arrow.clockwise")
                }
                .tint(.orange)
            }
            .contextMenu {
                Button {
                    item.isFavorite.toggle()
                } label: {
                    Label(item.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: item.isFavorite ? "star.slash" : "star.fill")
                }
                
                Button {
                    onReprocess()
                } label: {
                    Label("Reprocess", systemImage: "arrow.clockwise")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

struct ThumbnailView: View {
    let item: ProcessedItem
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 6
    
    var body: some View {
        Group {
            if let data = item.rawPayload, let uiImage = UIImage(data: data) {
                let isCutout = hasAlpha(uiImage)
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: isCutout ? .fit : .fill)
            } else if let snapshotPath = item.webContext?.snapshotURL, FileManager.default.fileExists(atPath: snapshotPath) {
                AsyncImage(url: URL(fileURLWithPath: snapshotPath)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    var fallbackIcon: some View {
        let config = ItemIconConfig.forItem(item)
        
        return ZStack {
            config.color.opacity(0.15)
            
            Image(systemName: config.iconName)
                .foregroundStyle(config.color)
                .font(.system(size: size * 0.5))
        }
    }
    
    private func hasAlpha(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let alpha = cgImage.alphaInfo
        return alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
    }
}

struct ItemIconConfig {
    let iconName: String
    let color: Color
    
    static func forItem(_ item: ProcessedItem) -> ItemIconConfig {
        // Check specific types first
        if let type = item.entityType?.lowercased() {
            switch type {
            case "document", "pdf":
                return ItemIconConfig(iconName: "doc.text.fill", color: .blue)
            case "link", "web", "page":
                return ItemIconConfig(iconName: "safari.fill", color: .cyan)
            case "image", "photo":
                return ItemIconConfig(iconName: "photo.fill", color: .purple)
            case "place", "venue", "landmark":
                return ItemIconConfig(iconName: "mappin.circle.fill", color: .red)
            case "activity", "event":
                return ItemIconConfig(iconName: "figure.run", color: .orange)
            case "video":
                return ItemIconConfig(iconName: "play.rectangle.fill", color: .pink)
            case "product":
                return ItemIconConfig(iconName: "cart.fill", color: .green)
            case "contact", "person":
                return ItemIconConfig(iconName: "person.crop.circle.fill", color: .indigo)
            case "qr", "qrcode":
                return ItemIconConfig(iconName: "qrcode", color: .gray)
            default:
                break
            }
        }
        
        // Fallback checks
        if item.placeContext != nil {
            return ItemIconConfig(iconName: "mappin.circle.fill", color: .red)
        }
        if item.rawPayload != nil {
            return ItemIconConfig(iconName: "photo.fill", color: .purple)
        }
        
        return ItemIconConfig(iconName: "square.fill", color: .gray)
    }
}

struct DailySummaryCard: View {
    @ObservedObject var service: DailyContextService
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S FOCUS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                if service.isGenerating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Updating summary...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(service.dailySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Label("Your Day", systemImage: "sun.max.fill")
                    .foregroundStyle(.orange)
                Spacer()
                if service.hasContent {
                    Button {
                        Task { await service.updateSummary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


extension SidebarView {
    private func sessions(in collection: DiverCollection) -> [DiverSession] {
        sessions.filter { collection.sessionIDs.contains($0.sessionID) }
                .sorted { $0.updatedAt > $1.updatedAt }
    }

    @ViewBuilder
    private func collectionSessionContextMenu(session: DiverSession, collection: DiverCollection) -> some View {
        // Set as Current (Priority Action)
        Button {
            viewModel.setSessionAsCurrent(session, context: modelContext)
        } label: {
            Label("Set as Current", systemImage: "clock.arrow.2.circlepath")
        }
        
        Button {
            collectionToRename = collection
            newCollectionName = collection.name
        } label: {
            Label("Rename Collection", systemImage: "pencil")
        }
        
        Button(role: .destructive) {
            viewModel.removeSessionFromCollection(sessionID: session.sessionID, context: modelContext)
        } label: {
            Label("Remove from Collection", systemImage: "folder.badge.minus")
        }
        
        Button(role: .destructive) {
            viewModel.deleteCollection(collection, context: modelContext)
        } label: {
            Label("Delete Collection", systemImage: "trash")
        }
        
        Button {
            sessionForLocationEdit = session
        } label: {
            Label("Edit Location", systemImage: "mappin.and.ellipse")
        }
        
        Button {
            sessionToRename = session
            newSessionTitle = session.displayTitle
        } label: {
            Label("Rename Session", systemImage: "pencil")
        }
        
        Button {
            analyzeSession(session)
        } label: {
            Label("Analyze Session", systemImage: "sparkles")
        }
        
        Divider()
        
        Button(role: .destructive) {
            viewModel.deleteSession(session, context: modelContext)
        } label: {
            Label("Delete Session", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func collectionGroup(for collection: DiverCollection) -> some View {
        DisclosureGroup {
            ForEach(sessions(in: collection)) { session in
                SidebarSessionRow(
                    session: session,
                    viewModel: viewModel,
                    allItems: allItems,
                    allConcepts: allConcepts,
                    onLocationEdit: { sessionForLocationEdit = $0 },
                    onRename: { s, t in sessionToRename = s; newSessionTitle = t },
                    onNewCollection: { s, t in sessionForNewCollection = s; newCollectionName = t; showingCreateCollection = true },
                    onAddSession: { s, c in viewModel.addSessionToCollection(session, collection: c, context: modelContext) },
                    collections: collections,
                    analyzeSession: { viewModel.analyzeSession($0, context: modelContext) }
                )
                .contextMenu {
                    collectionSessionContextMenu(session: session, collection: collection)
                }
                .draggable(SessionTransfer(id: session.sessionID))
                .dropDestination(for: ItemTransfer.self) { items, location in
                    // Allow dropping items into sessions inside collections
                    viewModel.moveItems(items, to: session, context: modelContext)
                    return true
                }
            }
        } label: {
            Label(collection.name, systemImage: "folder.fill")
                .foregroundStyle(.purple)
        }
        .dropDestination(for: SessionTransfer.self) { transfers, location in
            guard let transfer = transfers.first else { return false }
            viewModel.moveSessionToCollection(sessionID: transfer.id, collectionID: collection.collectionID, context: modelContext)
            return true
        }
        .dropDestination(for: ItemTransfer.self) { transfers, location in
            guard let transfer = transfers.first else { return false }
            // Create a NEW session INSIDE this collection with this item
            Task { @MainActor in
                viewModel.createSessionInCollectionWithItem(itemID: transfer.id, collectionID: collection.collectionID, context: modelContext)
            }
            return true
        }
    }
    
    @ViewBuilder
    private func standaloneSessionRow(for session: DiverSession) -> some View {
        SidebarSessionRow(
            session: session,
            viewModel: viewModel,
            allItems: allItems,
            allConcepts: allConcepts,
            onLocationEdit: { sessionForLocationEdit = $0 },
            onRename: { s, t in sessionToRename = s; newSessionTitle = t },
            onNewCollection: { s, t in sessionForNewCollection = s; newCollectionName = t; showingCreateCollection = true },
            onAddSession: { s, c in viewModel.addSessionToCollection(session, collection: c, context: modelContext) },
            collections: collections,
            analyzeSession: { viewModel.analyzeSession($0, context: modelContext) }
        )
    }
}
