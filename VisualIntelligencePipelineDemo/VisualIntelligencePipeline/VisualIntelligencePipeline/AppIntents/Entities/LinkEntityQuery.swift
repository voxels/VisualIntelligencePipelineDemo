// VisualIntelligencePipeline/VisualIntelligencePipeline/AppIntents/Entities/LinkEntityQuery.swift
import AppIntents
import SwiftData
import UIKit
import OSLog
import DiverShared
import DiverKit
import knowmaps

private let logger = Logger(subsystem: "com.secretatomics.VisualIntelligencePipeline", category: "AppIntents")


struct LinkEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) throws -> [LinkEntity] {
        logger.debug("🎬 [LinkEntityQuery] entities(for:) entry with \(identifiers.count) IDs")
        let context = try getContext()
        
        // Use a simple fetch and filter in-memory for maximum reliability in extensions
        let fetch = FetchDescriptor<ProcessedItem>()
        let allItems = try context.fetch(fetch)
        
        let items = allItems.filter { identifiers.contains($0.id) }
        logger.debug("📥 [LinkEntityQuery] entities(for:) found \(items.count) matches from \(allItems.count) total")
        
        var result = items.map(LinkEntity.init(processedItem:))
        
        #if DEBUG
        // tracer bullet for individual resolution
        if result.isEmpty, let firstId = identifiers.first {
             let debugItem = ProcessedItem(
                id: firstId,
                url: "https://debug.com",
                title: "Debug Resolve: \(firstId)",
                status: .ready
            )
            result.append(LinkEntity(processedItem: debugItem))
        }
        #endif
        
        return result
    }

    @MainActor
    func fetchAllEntities() throws -> [LinkEntity] {
        logger.debug("🎬 [LinkEntityQuery] suggestedEntities entry")
        
        // Attempt to fetch from context
        var items: [ProcessedItem] = []
        do {
            let context = try getContext()
            logger.debug("📡 [LinkEntityQuery] Context obtained, fetching items...")
            
            // Fetch more than needed to allow for in-memory filtering of status
            var fetch = FetchDescriptor<ProcessedItem>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            fetch.fetchLimit = 50
            
            let allItems = try context.fetch(fetch)
            logger.debug("📥 [LinkEntityQuery] Raw fetch complete: \(allItems.count) items")
            
            // Filter in-memory to avoid "Unsupported Predicate" crash with enums
            items = allItems.filter { $0.status == .ready }
            logger.debug("🧹 [LinkEntityQuery] Filtered for .ready status: \(items.count) items")
            
            logger.debug("🔍 [LinkEntityQuery] Final suggested items count: \(items.count)")
        } catch {
            logger.error("❌ [LinkEntityQuery] Context/Fetch failed: \(error.localizedDescription)")
            // We swallow the error here to allow returning the debug item if needed
        }
        
        logger.debug("🗺️ [LinkEntityQuery] Mapping items to entities")
        let result = items.map(LinkEntity.init(processedItem:))
        
        // Insert at top
        // result.insert(debugEntity, at: 0)
        
        logger.debug("🏁 [LinkEntityQuery] Returning \(result.count) entities total")
        return result
    }

    @MainActor
    func searchEntities(matching string: String) throws -> [LinkEntity] {
        logger.debug("🎬 [LinkEntityQuery] entities(matching:) entry for '\(string)'")
        let context = try getContext()
        
        // Fetch items and filter in memory
        let fetch = FetchDescriptor<ProcessedItem>()
        let allItems = try context.fetch(fetch)
        logger.debug("📥 [LinkEntityQuery] matching: fetched \(allItems.count) total items")
        
        let queryTokens = string.lowercased().split(separator: " ").map(String.init)
        
        let matches = allItems.filter { item in
            // Use raw value for comparison to avoid any enum-related fetch issues
            let isReady = item.status.rawValue == ProcessingStatus.ready.rawValue
            guard isReady else { return false }
            
            // Check if ALL query tokens are found in the searchable content
            return queryTokens.allSatisfy { token in
                let inTitle = item.title?.lowercased().contains(token) ?? false
                let inUrl = item.url?.lowercased().contains(token) ?? false
                let inSummary = item.summary?.lowercased().contains(token) ?? false
                let inTags = item.tags.contains { $0.lowercased().contains(token) }
                
                // Advanced fields
                let inEntityType = item.entityType?.lowercased().contains(token) ?? false
                let inModality = item.modality?.lowercased().contains(token) ?? false
                let inSource = item.source?.lowercased().contains(token) ?? false
                let inTranscription = item.transcription?.lowercased().contains(token) ?? false
                let inThemes = item.themes.contains { $0.lowercased().contains(token) }
                let inFilename = item.filename?.lowercased().contains(token) ?? false
                
                return inTitle || inUrl || inSummary || inTags || 
                       inEntityType || inModality || inSource || 
                       inTranscription || inThemes || inFilename
            }
        }
        logger.debug("🔍 [LinkEntityQuery] matching found: \(matches.count) for tokens: \(queryTokens)")
        return matches.map(LinkEntity.init(processedItem:))
    }

    @MainActor
    static var testContainer: ModelContainer?
    
    @MainActor
    private static var _cachedContainer: ModelContainer?

    @MainActor
    private func getContext() throws -> ModelContext {
        if let test = Self.testContainer {
            logger.debug("✅ Using test container")
            return test.mainContext
        }
        
        // Reuse main app container if available to avoid CloudKit conflicts
        if let shared = UnifiedDataManager.shared {
            logger.debug("✅ Using shared UnifiedDataManager container")
            return shared.mainContext
        }
        
        if let cached = Self._cachedContainer {
            logger.debug("✅ Using cached extension container")
            return ModelContext(cached)
        }

        logger.debug("🏗️ Creating new ModelContainer for extension")
        
        let diverTypes: [any PersistentModel.Type] = DiverDataStore.coreTypes + [
            UserCachedRecord.self,
            RecommendationData.self
        ]
        let schema = Schema(diverTypes)

        let appGroupURL = try AppGroupContainer.dataStoreURL()
        logger.debug("📂 App Group URL: \(appGroupURL.path)")
        
        let config = ModelConfiguration(schema: schema, url: appGroupURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        Self._cachedContainer = container
        return ModelContext(container)
    }
}
