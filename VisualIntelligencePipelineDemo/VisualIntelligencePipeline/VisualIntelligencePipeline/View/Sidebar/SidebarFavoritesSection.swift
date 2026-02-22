import SwiftUI
import SwiftData
import DiverKit

/// Owns its own `@Query` for favorite items and sessions — favorites changes
/// only re-render this section, not the entire sidebar.
struct SidebarFavoritesSection: View {
    // Own queries — isolated from parent re-render cycle
    @Query(filter: #Predicate<ProcessedItem> { $0.isFavorite == true }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var favoriteItems: [ProcessedItem]
    
    @Query(filter: #Predicate<SessionMetadata> { $0.isFavorite == true }, sort: \SessionMetadata.updatedAt, order: .reverse)
    private var favoriteSessions: [SessionMetadata]
    
    // Needed for parent session lookup when navigating to a favorite item
    @Query(sort: \SessionMetadata.updatedAt, order: .reverse)
    private var sessions: [SessionMetadata]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationManager: NavigationManager
    @Binding var selectedSession: SessionMetadata?
    var viewModel: SidebarViewModel
    
    var body: some View {
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
                        if let sessionID = item.sessionID {
                            if let session = sessions.first(where: { $0.sessionID == sessionID }) {
                                selectedSession = session
                                navigationManager.selectedSession = session
                            }
                        }
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
}
