import SwiftUI
import SwiftData
import DiverKit

struct ContentView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    let pipelineService: MetadataPipelineService
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $navigationManager.selection, pipelineService: pipelineService)
        } detail: {
            if let item = navigationManager.selection {
                ReferenceDetailView(item: item)
                    .id(item.id) // Force refresh when ID changes
            } else {
                ContentUnavailableView(
                    "Select an Item",
                    systemImage: "arrow.left",
                    description: Text("Choose an item from the sidebar to view details.")
                )
            }
        }
        .fullScreenCover(isPresented: $navigationManager.isScanActive) {
            VisualIntelligenceView()
        }
    }
}

// Preview removed due to complex dependency injection requirements.
