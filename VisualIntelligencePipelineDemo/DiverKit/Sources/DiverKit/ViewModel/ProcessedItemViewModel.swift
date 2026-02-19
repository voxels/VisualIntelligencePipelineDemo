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
        // Implementation for sharing logic (e.g. creating a shared link or exporting PDF)
        // This is a placeholder for actual sharing logic extracted from Views
    }
    
    /// Returns a list of related concepts for an item, sorted by weight.
    public func relatedConcepts(for item: ProcessedItem) -> [UserConcept] {
        // Business logic to extract and sort concepts
        return [] // Placeholder
    }
}
