//
//  ContentView.swift
//  VisualIntelligencePipeline
//
//  Three-pane navigation: Sidebar (Collections/Sessions) → Content (Items) → Detail
//

import SwiftUI
import SwiftData
import DiverKit

struct ContentView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    let pipelineService: MetadataPipelineService
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSession: $navigationManager.selectedSession,
                pipelineService: pipelineService
            )
        } content: {
            SessionItemsView(
                session: navigationManager.selectedSession,
                selection: $navigationManager.selection,
                pipelineService: pipelineService
            )
        } detail: {
            DetailPane(selection: navigationManager.selection)
        }
        .fullScreenCover(isPresented: $navigationManager.isScanActive) {
            VisualIntelligenceView()
                .environmentObject(navigationManager)
        }
    }
}

// MARK: - Detail Pane (extracted to fix type-check)

struct DetailPane: View {
    let selection: ProcessedItem?
    
    var body: some View {
        if let item = selection {
            ReferenceDetailView(item: item)
                .id(item.id)
        } else {
            ContentUnavailableView(
                "Select an Item",
                systemImage: "arrow.left",
                description: Text("Choose an item from the list to view details.")
            )
        }
    }
}

// MARK: - Session Items View (Content Pane)

struct SessionItemsView: View {
    let session: DiverSession?
    @Binding var selection: ProcessedItem?
    let pipelineService: MetadataPipelineService
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = SidebarViewModel()
    
    // Session Actions State
    @State private var sessionForLocationEdit: DiverSession?
    @State private var sessionToRename: DiverSession?
    @State private var newSessionTitle = ""
    @State private var showingDeleteConfirmation = false
    
    @Query(sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]
    
    @Query(sort: \DiverCollection.updatedAt, order: .reverse)
    private var collections: [DiverCollection]
    
    private var sessionItems: [ProcessedItem] {
        guard let session = session else { return [] }
        return allItems.filter { 
            $0.sessionID == session.sessionID && $0.status == .ready 
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var body: some View {
        Group {
            if let _ = session {
                itemList
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "photo.stack",
                    description: Text("Choose a session from the sidebar to view its items.")
                )
            }
        }
        .sheet(item: $viewModel.itemToReprocess) { item in
            ReprocessMetadataView(item: item)
        }
        .sheet(item: $viewModel.itemToDuplicate) { item in
            SessionPickerSheet(item: item, viewModel: viewModel)
        }
        .sheet(item: $sessionForLocationEdit) { session in
            EditSessionLocationView(session: session)
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
                }
                sessionToRename = nil
                newSessionTitle = ""
            }
        } message: {
            Text("Enter a new title for this session")
        }
        .alert("Delete Session?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let session = session {
                    deleteSession(session)
                }
            }
        } message: {
            Text("This will delete the session and all its items. This action cannot be undone.")
        }
    }
    
    private var itemList: some View {
        List(selection: $selection) {
            Section {
                ForEach(sessionItems) { item in
                    ItemRowContainer(
                        item: item,
                        viewModel: viewModel,
                        modelContext: modelContext,
                        selection: $selection
                    )
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sessionTitle(for: session!))
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let summary = session?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let session = session {
                         // Placeholder if summary is regenerating
                         Text("Analyzing session...")
                             .font(.caption)
                             .foregroundStyle(.secondary)
                             .italic()
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
                .textCase(nil) // Prevent automatic uppercase for headers
            }
        }
        .navigationTitle("") // Hide default title to avoid truncation/duplication
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ProcessedItem.self) { item in
            ReferenceDetailView(item: item)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let session = session {
                    sessionActionsMenu(for: session)
                }
            }
        }
    }
    
    // MARK: - Session Actions Menu
    
    @ViewBuilder
    private func sessionActionsMenu(for session: DiverSession) -> some View {
        Menu {
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
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private func sessionTitle(for session: DiverSession) -> String {
        if let title = session.title, !title.isEmpty {
            return title
        }
        if let location = session.locationName, !location.isEmpty {
            return location
        }
        return session.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
    
    private func deleteItem(_ item: ProcessedItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
    
    private func deleteSession(_ session: DiverSession) {
        // Delete all items in the session
        for item in sessionItems {
            modelContext.delete(item)
        }
        // Delete the session itself
        modelContext.delete(session)
        try? modelContext.save()
    }
    
    private func analyzeSession(_ session: DiverSession) {
        Task {
            let localPipeline = LocalPipelineService(modelContext: modelContext)
            await localPipeline.generateAndSaveSessionSummary(sessionID: session.sessionID)
            print("✅ Triggered analysis for session: \(session.title ?? session.sessionID)")
        }
    }
}

// MARK: - Item Row Button (extracted to fix type-check)

struct ItemRowButton: View {
    let item: ProcessedItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onReprocess: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ItemRow(item: item)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onReprocess) {
                Label("Reprocess", systemImage: "arrow.clockwise")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                item.isFavorite.toggle()
            } label: {
                Label(
                    item.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: item.isFavorite ? "star.slash" : "star.fill"
                )
            }
            
            Button(action: onReprocess) {
                Label("Reprocess", systemImage: "arrow.clockwise")
            }
            
            Divider()
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Extracted Row for Performance and to fix Scope
@MainActor
struct ItemRowContainer: View {
    let item: ProcessedItem
    @ObservedObject var viewModel: SidebarViewModel
    let modelContext: ModelContext
    @Binding var selection: ProcessedItem?
    
    var body: some View {
        NavigationLink(value: item) {
            ItemRow(item: item)
        }
        .draggable(ItemTransfer(id: item.id))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { viewModel.itemToReprocess = item } label: {
                Label("Reprocess", systemImage: "arrow.clockwise")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                item.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    item.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: item.isFavorite ? "star.slash" : "star"
                )
            }
            
            Divider()
            
            Button {
                viewModel.itemToEditLocation = item
            } label: {
                Label("Edit Location", systemImage: "mappin.and.ellipse")
            }
            
            Button {
                viewModel.itemToDuplicate = item
            } label: {
                Label("Duplicate to Session...", systemImage: "plus.square.on.square")
            }
            
            Button {
                viewModel.itemToReprocess = item
            } label: {
                Label("Reprocess", systemImage: "arrow.clockwise")
            }
        }
    }
}

// MARK: - Session Picker Sheet

struct SessionPickerSheet: View {
    let item: ProcessedItem
    @ObservedObject var viewModel: SidebarViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \DiverSession.updatedAt, order: .reverse)
    private var sessions: [DiverSession]
    
    @State private var searchText = ""
    
    var filteredSessions: [DiverSession] {
        if searchText.isEmpty {
            return sessions
        } else {
            return sessions.filter { 
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) || 
                ($0.locationName ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSessions) { session in
                    Button {
                        viewModel.duplicateItem(item, to: session, context: modelContext)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.displayTitle)
                                    .foregroundStyle(.primary)
                                if let loc = session.locationName {
                                    Text(loc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if session.sessionID == item.sessionID {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(session.sessionID == item.sessionID)
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions...")
            .navigationTitle("Duplicate into Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
