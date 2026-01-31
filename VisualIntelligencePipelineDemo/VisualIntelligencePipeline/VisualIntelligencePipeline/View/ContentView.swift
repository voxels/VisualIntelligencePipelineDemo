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
    
    @Query(sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]
    
    private var sessionItems: [ProcessedItem] {
        guard let session = session else { return [] }
        return allItems.filter { 
            $0.sessionID == session.sessionID && $0.status == .ready 
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var body: some View {
        Group {
            if let session = session {
                itemList
                    .navigationTitle(sessionTitle(for: session))
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
    }
    
    private var itemList: some View {
        List {
            ForEach(sessionItems) { item in
                ItemRowButton(
                    item: item,
                    isSelected: selection?.id == item.id,
                    onSelect: { selection = item },
                    onDelete: { deleteItem(item) },
                    onReprocess: { viewModel.itemToReprocess = item }
                )
            }
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
