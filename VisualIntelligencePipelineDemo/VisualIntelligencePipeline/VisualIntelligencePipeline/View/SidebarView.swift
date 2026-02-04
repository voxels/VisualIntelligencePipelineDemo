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
    
    /// Get items for a specific session
    private func items(for sessionID: String) -> [ProcessedItem] {
        readyItems.filter { $0.sessionID == sessionID }
            .sorted { ($0.updatedAt) > ($1.updatedAt) }
    }
    
    /// Get sessions for a collection
    private func sessions(for collection: DiverCollection) -> [DiverSession] {
        sessions.filter { collection.sessionIDs.contains($0.sessionID) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Delete an item from the database
    private func deleteItem(_ item: ProcessedItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
    
    /// Delete a session and all its items from the database
    private func deleteSession(_ session: DiverSession, items: [ProcessedItem]) {
        // Delete all items in the session
        for item in items {
            modelContext.delete(item)
        }
        // Delete the session itself
        modelContext.delete(session)
        try? modelContext.save()
    }
    
    /// Delete a collection and all its sessions and items from the database
    private func deleteCollection(_ collection: DiverCollection, sessions: [DiverSession], items: [ProcessedItem]) {
        // Delete all items
        for item in items {
            modelContext.delete(item)
        }
        // Delete all sessions
        for session in sessions {
            modelContext.delete(session)
        }
        // Delete the collection itself
        modelContext.delete(collection)
        try? modelContext.save()
    }
    
    /// Delete all selected sessions and their items
    private func deleteSelectedSessions() {
        for sessionID in viewModel.selectedSessions {
            // Find the session
            if let session = sessions.first(where: { $0.sessionID == sessionID }) {
                // Delete all items in this session
                let items = allItems.filter { $0.sessionID == sessionID }
                for item in items {
                    modelContext.delete(item)
                }
                // Delete the session
                modelContext.delete(session)
            }
        }
        try? modelContext.save()
        
        // Clear selection and exit selection mode
        viewModel.selectedSessions.removeAll()
        viewModel.isSelectionMode = false
    }
    
    /// Add a session to an existing collection
    private func addSession(_ session: DiverSession, to collection: DiverCollection) {
        if !collection.sessionIDs.contains(session.sessionID) {
            collection.sessionIDs.append(session.sessionID)
            collection.updatedAt = Date()
            try? modelContext.save()
            print("✅ Added session '\(session.title ?? session.sessionID)' to collection '\(collection.name)'")
        }
    }
    
    /// Create a new collection with a session
    private func createCollection(name: String, with session: DiverSession) {
        let collection = DiverCollection(
            name: name,
            sessionIDs: [session.sessionID]
        )
        modelContext.insert(collection)
        try? modelContext.save()
        print("✅ Created collection '\(name)' with session '\(session.title ?? session.sessionID)'")
    }
    
    /// Get display title for a session
    private func sessionTitle(for session: DiverSession) -> String {
        if let title = session.title, !title.isEmpty {
            return title
        }
        if let location = session.locationName, !location.isEmpty {
            return location
        }
        return session.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
    
    /// Create a new note document for the session and open for editing
    private func createNewNoteForSession(_ session: DiverSession) {
        Task {
            // Create the note item DIRECTLY as ready, skipping queue processing
            let noteID = UUID().uuidString
            
            await MainActor.run {
                let newNote = ProcessedItem(
                    id: noteID,
                    title: "Session Note",
                    entityType: "document",
                    sessionID: session.sessionID
                )
                
                // Set note properties
                newNote.tags = ["note"]
                newNote.categories = ["note"]
                newNote.transcription = "" // Start empty for user to type
                newNote.status = .ready // Ready immediately, no processing needed
                
                // Copy location name from session
                newNote.location = session.locationName
                
                // Insert into context
                modelContext.insert(newNote)
                
                do {
                    try modelContext.save()
                    print("✅ Created note directly, opening for editing: \(noteID)")
                    
                    // Set session first to populate middle pane
                    navigationManager.selectedSession = session
                    
                    // Then select the item to show detail immediately
                    navigationManager.selection = newNote
                } catch {
                    print("❌ Failed to save note: \(error)")
                }
            }
        }
    }
    
    /// Get concepts most related to a session based on tags and categories
    /// Now includes allItems dependency to ensure updates when categories change
    private func relatedConcepts(for session: DiverSession) -> [UserConcept] {
        // Force dependency on allItems to trigger recomputation
        let sessionItems = allItems.filter { $0.sessionID == session.sessionID }
        
        // Collect all tags, categories, AND purposes from session items
        var sessionTerms = Set<String>()
        for item in sessionItems {
            sessionTerms.formUnion(item.tags)
            sessionTerms.formUnion(item.categories)
            sessionTerms.formUnion(item.purposes)
        }
        
        // Match concepts by EXACT name equality (case-insensitive) for better relevance
        // Filter out generic "At:" location purposes
        let meaningfulTerms = sessionTerms.filter { !$0.hasPrefix("At: ") }
        let related = allConcepts.filter { concept in
            meaningfulTerms.contains { term in
                term.lowercased() == concept.name.lowercased()
            }
        }
        
        // Return top 5 by weight (sorted)
        return Array(related.sorted(by: { $0.weight > $1.weight }).prefix(5))
    }
    
    // MARK: - Body
    
    var body: some View {
        List(selection: $selectedSession) {
            // Intelligence Actions
            intelligenceSection
            
            // Daily Summary
            if let service = Services.shared.dailyContextService {
                DailySummaryCard(service: service)
            }
            
            // Collections with Sessions
            librarySection
            
            // Shared with You
            if #available(iOS 16.0, *) {
                SharedWithYouView(manager: sharedWithYouManager)
            }
            
            // Standalone Sessions (Removed, now in librarySection)
            
            // Processing Items - moved above Memory/Today
            if !processingItems.isEmpty {
                processingSection
            }
            
            // Memory/Concepts
            memorySection
        }
        .listStyle(.sidebar)
        .navigationTitle("Visual Intelligence")
        .searchable(text: $viewModel.searchText, prompt: "Search items...")
        .refreshable {
            await viewModel.refresh()
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
            SettingsView()
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
            Task {
                await importSelectedPhotos(newValue)
                selectedPhotos = []
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
                    createCollection(name: newCollectionName, with: session)
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
                    collection.name = newCollectionName
                    collection.updatedAt = Date()
                    try? modelContext.save()
                    print("✅ Renamed collection to '\(newCollectionName)'")
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
                    session.title = newSessionTitle
                    session.updatedAt = Date()
                    try? modelContext.save()
                    print("✅ Renamed session to '\(newSessionTitle)'")
                }
                sessionToRename = nil
                newSessionTitle = ""
            }
        } message: {
            Text("Enter a new title for this session")
        }
    }
    
    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        // Use the proper PhotoLibraryImportService for clustering, session creation, and metadata extraction
        let importService = PhotoLibraryImportService(modelContext: modelContext)
        
        // Generate a collection name based on current date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let collectionName = "Import \(dateFormatter.string(from: Date()))"
        
        do {
            let collection = try await importService.importItems(items, collectionName: collectionName)
            print("✅ Imported \(items.count) photos into collection: \(collection.name)")
            
            // Process the imported items through the pipeline
            try? await pipelineService.processPendingQueue()
        } catch {
            print("❌ Failed to import photos: \(error)")
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var librarySection: some View {
        Section("Library") {
            // 1. Collections (Folders)
            ForEach(collections) { collection in
                DisclosureGroup {
                    ForEach(sessions(for: collection)) { session in
                        NavigationLink(value: session) {
                            SessionRowLabel(session: session, allItems: allItems)
                        }
                        .contextMenu {
                            Button {
                                sessionForLocationEdit = session
                            } label: {
                                Label("Edit Location", systemImage: "mappin.and.ellipse")
                            }
                            
                            Button {
                                sessionToRename = session
                                newSessionTitle = sessionTitle(for: session)
                            } label: {
                                Label("Rename Session", systemImage: "pencil")
                            }
                            
                            Button {
                                analyzeSession(session)
                            } label: {
                                Label("Analyze Session", systemImage: "sparkles")
                            }
                            
                            Button(role: .destructive) {
                                let items = allItems.filter { $0.sessionID == session.sessionID }
                                deleteSession(session, items: items)
                            } label: {
                                Label("Delete Session", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Label(collection.name, systemImage: "folder.fill")
                        .foregroundStyle(.purple)
                }
                .contextMenu {
                    Button {
                       collectionToRename = collection
                       newCollectionName = collection.name
                    } label: {
                        Label("Rename Collection", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        let sess = sessions(for: collection)
                        let items = allItems.filter { item in
                            sess.contains { $0.sessionID == item.sessionID }
                        }
                        deleteCollection(collection, sessions: sess, items: items)
                    } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                }
            }
            
            // 2. Standalone Sessions (Files)
            ForEach(standaloneSessions) { session in
                if viewModel.isSelectionMode {
                    // Selection mode: tap to select, show checkmark
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
                } else {
                    // Normal mode: navigate to session
                    NavigationLink(value: session) {
                        SessionRowLabel(session: session, allItems: allItems)
                    }
                    .contextMenu {
                        // Add to existing collection
                        if !collections.isEmpty {
                            Menu {
                                ForEach(collections) { collection in
                                    Button {
                                        addSession(session, to: collection)
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
                            sessionForNewCollection = session
                            newCollectionName = sessionTitle(for: session)
                            showingCreateCollection = true
                        } label: {
                            Label("Create New Collection", systemImage: "folder.fill.badge.plus")
                        }
                        
                        Button {
                            sessionForLocationEdit = session
                        } label: {
                            Label("Edit Location", systemImage: "mappin.and.ellipse")
                        }
                        
                        Button {
                            sessionToRename = session
                            newSessionTitle = sessionTitle(for: session)
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
                            let items = allItems.filter { $0.sessionID == session.sessionID }
                            deleteSession(session, items: items)
                        } label: {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                }
            }
            
            // Delete selected button
            if viewModel.isSelectionMode && !viewModel.selectedSessions.isEmpty {
                Button(role: .destructive) {
                    deleteSelectedSessions()
                } label: {
                    Label("Delete \(viewModel.selectedSessions.count) Selected", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
    }
    

    
    @ViewBuilder
    private var intelligenceSection: some View {
        if IntelligenceCapability.isAvailable {
            Section("Current Context") {
                if let lastSession = sessions.first {
                    // Full contextual summary
                    if let summary = lastSession.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    
                    // Related concepts chips
                    let concepts = relatedConcepts(for: lastSession)
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
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // New Note button - creates empty document for this session
                    Button {
                        createNewNoteForSession(lastSession)
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
    }
    
    private func previewImage(for session: DiverSession) -> UIImage? {
        let items = allItems.filter { $0.sessionID == session.sessionID }
        for item in items {
            if let data = item.rawPayload, let image = UIImage(data: data) {
                return image
            }
            // Add other checks if needed (e.g. cached thumbnails)
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
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
                            processItemNow(item)
                        } label: {
                            Label("Process Now", systemImage: "bolt.fill")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            cancelProcessing(item)
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
    private func processItemNow(_ item: ProcessedItem) {
        Task {
            do {
                try await pipelineService.processItemImmediately(item)
                print("✅ Triggered immediate processing for: \(item.title ?? item.id)")
                // Status change is saved in the service; @Query should auto-update
            } catch {
                print("❌ Failed to process item immediately: \(error)")
            }
        }
    }
    
    /// Cancel processing for an item
    private func cancelProcessing(_ item: ProcessedItem) {
        item.status = .failed
        item.processingLog.append("\(Date().formatted()): Cancelled by user")
        try? modelContext.save()
        print("🚫 Cancelled processing for: \(item.title ?? item.id)")
    }
    
    
    
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
    
    /// Trigger session analysis
    private func analyzeSession(_ session: DiverSession) {
        Task {
            let localPipeline = LocalPipelineService(modelContext: modelContext)
            await localPipeline.generateAndSaveSessionSummary(sessionID: session.sessionID)
            print("✅ Triggered analysis for session: \(session.title ?? session.sessionID)")
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
        if let first = sessionItems.first {
            return ItemIconConfig.forItem(first)
        }
        return ItemIconConfig(iconName: "photo.stack", color: .secondary)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image with overlay text
            if let image = heroImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
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
            if let summary = session.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
            } else {
                Text("No Summary Available (ID: \(session.sessionID.prefix(4)))")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Item Row

struct ItemRow: View {
    let item: ProcessedItem
    
    private var displayTitle: String {
        item.title ?? item.url ?? "Untitled"
    }
    
    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.updatedAt, relativeTo: Date())
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
                
                HStack(spacing: 4) {
                    if let entityType = item.entityType {
                        Text(entityType.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .foregroundStyle(.tertiary)
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
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
                        .lineLimit(4)
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
