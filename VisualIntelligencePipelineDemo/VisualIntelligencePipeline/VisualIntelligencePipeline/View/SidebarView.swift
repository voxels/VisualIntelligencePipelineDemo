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
    @Binding var selectedSession: SessionMetadata?
    @State private var viewModel = SidebarViewModel()
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
    @State private var sessionToAddToCollection: SessionMetadata?
    @State private var showingCreateCollection = false
    @State private var sessionForNewCollection: SessionMetadata?
    @State private var sessionForLocationEdit: SessionMetadata?
    @State private var newCollectionName = ""
    
    // Queue Progress State (fed by AsyncStream)
    @State private var queueIsProcessing = false
    @State private var queueTotalCount = 0
    @State private var queueCompletedCount = 0
    @State private var queueCurrentItemTitle: String? = nil
    @State private var queueStatusMessage: String? = nil
    @State private var queueProgress: Double = 0
    
    // Collection Renaming State
    @State private var collectionToRename: SessionCollection?
    
    // Session Renaming State
    @State private var sessionToRename: SessionMetadata?
    @State private var newSessionTitle = ""
    
    // Agentic Search State
    @State private var showingAgenticChat = false
    
    // MARK: - Queries
    @Query(sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]
    
    @Query(filter: #Predicate<ProcessedItem> { $0.isFavorite == true }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var favoriteItems: [ProcessedItem]
    
    @Query(sort: \SessionCollection.updatedAt, order: .reverse)
    private var collections: [SessionCollection]
    
    @Query(sort: \SessionMetadata.updatedAt, order: .reverse)
    private var sessions: [SessionMetadata]
    
    @Query(filter: #Predicate<SessionMetadata> { $0.isFavorite == true }, sort: \SessionMetadata.updatedAt, order: .reverse)
    private var favoriteSessions: [SessionMetadata]
    
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
    private var standaloneSessions: [SessionMetadata] {
        sessions.filter { !collectionSessionIDs.contains($0.sessionID) }
    }
    
    /// Items with no sessionID
    private var uncategorizedItems: [ProcessedItem] {
        readyItems.filter { $0.sessionID == nil }
    }
    
    
    // MARK: - Library Sorting
    
    private enum LibraryItem: Identifiable {
        case collection(SessionCollection)
        case session(SessionMetadata)
        
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
            
            // Agentic Search Entry Point
            agenticSearchSection
            
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
            // 1. Push any local changes to CloudKit
            try? modelContext.save()
            
            // 2. Process pending queue items
            await viewModel.refresh(context: modelContext)
            
            // 3. Refresh Shared with You highlights
            if #available(iOS 16.0, macOS 13.0, *) {
                sharedWithYouManager.refreshHighlights()
            }
        }
        .onAppear {
            viewModel.setPipelineService(pipelineService)
            // Clean up empty/abandoned sessions on appear
            viewModel.removeEmptySessions(context: modelContext)
        }
        .task {
            for await event in pipelineService.progressStream {
                switch event {
                case .started(let totalCount):
                    queueIsProcessing = true
                    queueTotalCount = totalCount
                    queueCompletedCount = 0
                    queueCurrentItemTitle = nil
                    queueStatusMessage = "Starting…"
                    queueProgress = 0
                    
                case .processingItem(let completed, let total, let title, let status):
                    queueIsProcessing = true
                    queueTotalCount = total
                    queueCompletedCount = completed
                    queueCurrentItemTitle = title
                    queueStatusMessage = status
                    queueProgress = event.progress
                    
                case .itemCompleted(let completed, let total):
                    queueCompletedCount = completed
                    queueTotalCount = total
                    queueProgress = event.progress
                    
                case .completed:
                    queueStatusMessage = "Complete"
                    queueProgress = 1.0
                    // Delay hiding the overlay to show completion briefly
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    queueIsProcessing = false
                    queueTotalCount = 0
                    queueCompletedCount = 0
                    queueStatusMessage = nil
                    queueCurrentItemTitle = nil
                    
                case .cancelled:
                    queueIsProcessing = false
                    queueTotalCount = 0
                    queueCompletedCount = 0
                    queueStatusMessage = nil
                    queueCurrentItemTitle = nil
                    queueProgress = 0
                }
            }
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
            VStack(spacing: 8) {
                if viewModel.isMaintaining {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.maintenanceProgress)
                            .progressViewStyle(.linear)
                        Text("Rebuilding Library (\(Int(viewModel.maintenanceProgress * 100))%)...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .glassEffect()
                    .cornerRadius(8)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                queueProgressOverlay
            }
            .padding(.bottom, 8)
        }
        .overlay {
            if viewModel.isPerformingAction {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(24)
                        .glass(cornerRadius:16)

                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isPerformingAction)
            }
        }
        .allowsHitTesting(!viewModel.isPerformingAction)
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
                    .accessibilityIdentifier("settingsButton")
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
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotos) { oldValue, newValue in
            guard !newValue.isEmpty else { return }
            // Route through the Visual Intelligence review screen for full pipeline processing
            navigationManager.pendingImportItems = newValue
            if let target = viewModel.importTargetSession {
                navigationManager.scanSessionID = target.sessionID
            }
            navigationManager.isScanActive = true
            selectedPhotos = []
            viewModel.importTargetSession = nil
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
        .alert("Import Status", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.importError = nil
            }
        } message: {
            if let error = viewModel.importError {
                Text(error)
            }
        }
        .fullScreenCover(isPresented: $showingAgenticChat) {
            if let searchService = Services.shared.agenticSearchService {
                AgenticChatView(viewModel: AgenticChatViewModel(searchService: searchService))
            } else {
                Text("Agentic Search Service Unavailable")
                    .onTapGesture { showingAgenticChat = false }
            }
        }
    }
    
    private var agenticSearchSection: some View {
        Section {
            Button {
                showingAgenticChat = true
            } label: {
                Label("Chat with Librarian", systemImage: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.headline)
                    .padding(.vertical, 4)
            }
        }
    }
    
    @ViewBuilder
    private var queueProgressOverlay: some View {
        if queueIsProcessing {
            QueueProgressView(
                totalCount: queueTotalCount,
                completedCount: queueCompletedCount,
                currentItemTitle: queueCurrentItemTitle,
                statusMessage: queueStatusMessage,
                progress: queueProgress
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: queueIsProcessing)
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
        Section {
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
        } header: {
            Text("Library")
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
                        if let newSession = viewModel.createStandaloneSessionWithItem(itemID: transfer.id, context: modelContext) {
                            selectedSession = newSession
                        }
                    }
                    return true
                }
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
    
    private func previewImage(for session: SessionMetadata) -> UIImage? {
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
                        Label("Delete Item", systemImage: "trash")
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
                                    _ = viewModel.createSessionWithItem(item, in: collection, context: modelContext)
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
                            Text(item.title ?? item.displayLabel)
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


extension SidebarView {
    private func sessions(in collection: SessionCollection) -> [SessionMetadata] {
        sessions.filter { collection.sessionIDs.contains($0.sessionID) }
                .sorted { $0.updatedAt > $1.updatedAt }
    }

    @ViewBuilder
    private func collectionSessionContextMenu(session: SessionMetadata, collection: SessionCollection) -> some View {
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
            viewModel.analyzeSession(session, context: modelContext)
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
    private func collectionGroup(for collection: SessionCollection) -> some View {
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
                .dropDestination(for: SessionTransfer.self) { transfers, location in
                    guard let transfer = transfers.first else { return false }
                    viewModel.moveSessionToCollection(sessionID: transfer.id, collectionID: collection.collectionID, context: modelContext)
                    return true
                }
                .dropDestination(for: ItemTransfer.self) { transfers, location in
                    guard let transfer = transfers.first else { return false }
                    // Create a NEW session INSIDE this collection with this item
                    Task { @MainActor in
                        if let newSession = viewModel.createSessionInCollectionWithItem(itemID: transfer.id, collectionID: collection.collectionID, context: modelContext) {
                            selectedSession = newSession
                        }
                    }
                    return true
                }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.deleteCollection(collection, context: modelContext)
            } label: {
                Label("Delete Collection", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
             Button {
                 collectionToRename = collection
                 newCollectionName = collection.name
             } label: {
                 Label("Rename", systemImage: "pencil")
             }
             .tint(.blue)
        }
    }
    
    @ViewBuilder
    private func standaloneSessionRow(for session: SessionMetadata) -> some View {
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
