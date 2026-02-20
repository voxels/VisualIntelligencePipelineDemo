import SwiftUI
import SwiftData
import DiverShared

/// A ViewModel for handling business logic related to individual `ProcessedItem` objects.
/// This decouples the UI from the underlying storage and processing services.
@MainActor
public final class ProcessedItemViewModel: ObservableObject {
    private let modelContext: ModelContext
    private let pipeline: MetadataPipelineService
    
    public init(modelContext: ModelContext, pipeline: MetadataPipelineService) {
        self.modelContext = modelContext
        self.pipeline = pipeline
    }
    
    public func toggleFavorite(for item: ProcessedItem) {
        item.isFavorite.toggle()
        Task { @MainActor in
            try? modelContext.save()
        }
    }
    
    public func reprocessItem(_ item: ProcessedItem) {
        let itemID = item.id
        Task.detached(priority: .utility) { [pipeline] in
            try? await pipeline.processItemByID(itemID)
        }
    }
    
    public func deleteItem(_ item: ProcessedItem) {
        modelContext.delete(item)
        Task { @MainActor in
            try? modelContext.save()
        }
    }
    
    public func shareItem(_ item: ProcessedItem) {
        // Build shareable content from the item
        var shareItems: [Any] = []
        
        if let title = item.title {
            shareItems.append(title)
        }
        
        if let summary = item.summary {
            shareItems.append(summary)
        }
        
        if let urlString = item.url, let url = URL(string: urlString) {
            shareItems.append(url)
        }
        
        // Post notification for the UI layer to present the share sheet
        NotificationCenter.default.post(
            name: .shareItemRequested,
            object: nil,
            userInfo: ["shareItems": shareItems, "itemID": item.id]
        )
    }
    
    /// Returns a list of related concepts for an item, sorted by weight.
    public func relatedConcepts(for item: ProcessedItem) -> [UserConcept] {
        let tags = item.tags
        guard !tags.isEmpty else { return [] }
        
        // Fetch all concepts from the context and match by tag overlap
        let descriptor = FetchDescriptor<UserConcept>()
        let allConcepts = (try? modelContext.fetch(descriptor)) ?? []
        
        return allConcepts
            .filter { concept in
                tags.contains(where: { tag in
                    concept.name.localizedCaseInsensitiveContains(tag)
                })
            }
            .sorted { ($0.weight) > ($1.weight) }
    }
}

public extension Notification.Name {
    static let shareItemRequested = Notification.Name("shareItemRequested")
}
