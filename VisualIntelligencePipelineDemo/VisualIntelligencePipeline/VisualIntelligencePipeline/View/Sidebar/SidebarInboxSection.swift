import SwiftUI
import SwiftData
import DiverKit

/// Owns its own `@Query` for uncategorized items — inbox changes
/// only re-render this section, not the entire sidebar.
struct SidebarInboxSection: View {
    // Fetch only items with no sessionID — simpler predicate to avoid type-checker timeout.
    // Filter out queued/processing/failed in the computed property below.
    @Query(filter: #Predicate<ProcessedItem> { $0.sessionID == nil }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allUncategorizedItems: [ProcessedItem]
    
    @Query(sort: \SessionCollection.updatedAt, order: .reverse)
    private var collections: [SessionCollection]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationManager: NavigationManager
    var viewModel: SidebarViewModel
    
    /// Filter out processing/queued/failed items in-memory to keep predicate simple
    private var uncategorizedItems: [ProcessedItem] {
        allUncategorizedItems.filter { item in
            let status = item.statusRaw
            return status != "queued" && status != "processing" && status != "failed"
        }
    }
    
    var body: some View {
        if !uncategorizedItems.isEmpty {
            Section("Inbox") {
                ForEach(uncategorizedItems) { item in
                    Button {
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
    }
}
