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
    
    // MARK: - Queries
    @Query(sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]
    
    @Query(filter: #Predicate<ProcessedItem> { $0.isFavorite == true }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var favoriteItems: [ProcessedItem]
    
    @Query(sort: \DiverCollection.updatedAt, order: .reverse)
    private var collections: [DiverCollection]
    
    @Query(sort: \DiverSession.updatedAt, order: .reverse)
    private var sessions: [DiverSession]
    
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
    
    // MARK: - Body
    
    var body: some View {
        List(selection: $selectedSession) {
            // Intelligence Actions
            intelligenceSection
            
            // Collections with Sessions
            if !collections.isEmpty {
                collectionsSection
            }
            
            // Standalone Sessions (not in any collection)
            if !standaloneSessions.isEmpty {
                sessionsSection
            }
            
            // Processing Items
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
    private var intelligenceSection: some View {
        if IntelligenceCapability.isAvailable {
            Section("Intelligence") {
                Button {
                    navigationManager.isScanActive = true
                } label: {
                    Label("Scan for context", systemImage: "sparkles.tv")
                        .foregroundStyle(.cyan)
                }
            }
        }
    }
    
    
    
    @ViewBuilder
    private var collectionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $collectionsExpanded) {
                ForEach(collections) { collection in
                    DisclosureGroup {
                        ForEach(sessions(for: collection)) { session in
                            NavigationLink(value: session) {
                                SessionRowLabel(session: session, allItems: allItems)
                            }
                            .contextMenu {
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
            } label: {
                Label("Collections", systemImage: "rectangle.stack.fill")
                    .foregroundStyle(.indigo)
            }
        }
    }
    
    @ViewBuilder
    private var sessionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $sessionsExpanded) {
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
            } label: {
                Label("Sessions", systemImage: "photo.stack")
                    .foregroundStyle(.blue)
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
                        Text(item.title ?? item.url ?? "Processing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("Processing (\(processingItems.count))", systemImage: "gear")
                    .foregroundStyle(.orange)
            }
        }
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
}

// MARK: - Session Row Label (for 3-pane navigation)

struct SessionRowLabel: View {
    let session: DiverSession
    let allItems: [ProcessedItem]
    
    private var sessionTitle: String {
        if let title = session.title, !title.isEmpty {
            return title
        }
        if let location = session.locationName, !location.isEmpty {
            return location
        }
        return session.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
    
    private var sessionItems: [ProcessedItem] {
        allItems.filter { $0.sessionID == session.sessionID && $0.status == .ready }
    }
    
    var body: some View {
        HStack {
            // Thumbnail
            if let firstItem = sessionItems.first,
               let data = firstItem.rawPayload,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text("\(sessionItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
        if let data = item.rawPayload, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let snapshotPath = item.webContext?.snapshotURL {
            AsyncImage(url: URL(fileURLWithPath: snapshotPath)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: iconName)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
        }
    }
    
    private var iconName: String {
        switch item.entityType {
        case "document": return "doc.fill"
        case "page", "link": return "safari"
        case "image": return "photo"
        case "product": return "bag"
        default: return "square"
        }
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
