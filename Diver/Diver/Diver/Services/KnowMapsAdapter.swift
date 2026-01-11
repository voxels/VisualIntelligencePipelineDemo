import Foundation
import knowmaps
import DiverShared
import DiverKit
import SwiftData

enum KnowMapsAdapter {
    struct CacheRecordPayload: Equatable {
        let recordId: String
        let group: String
        let identity: String
        let title: String
        let icons: String
        let list: String
        let section: String
        let rating: Double
    }

    static let cacheGroup = "DiverItem"
    static let defaultSection = PersonalizedSearchSection.topPicks.rawValue

    static func metadata(from item: Item) -> ItemMetadata {
        guard let descriptor = item.descriptor else {
            return ItemMetadata(
                id: item.id,
                title: item.title,
                descriptionText: item.descriptionText,
                styleTags: item.styleTags,
                categories: item.categories,
                location: item.location,
                price: item.price
            )
        }
        return metadata(from: descriptor)
    }

    static func metadata(from descriptor: DiverItemDescriptor) -> ItemMetadata {
        ItemMetadata(
            id: descriptor.id,
            title: descriptor.title,
            descriptionText: descriptor.descriptionText,
            styleTags: descriptor.styleTags + descriptor.purposes, // Map purposes to styleTags so they are persisted
            categories: descriptor.categories,
            location: descriptor.location,
            price: descriptor.price
        )
    }

    static func cachedRecord(
        from item: Item,
        rating: Double = 1,
        list: String? = nil,
        section: String = defaultSection
    ) -> UserCachedRecord {
        cachedRecord(from: cachePayload(from: item, rating: rating, list: list, section: section))
    }

    static func cachePayload(
        from item: Item,
        rating: Double = 1,
        list: String? = nil,
        section: String = defaultSection
    ) -> CacheRecordPayload {
        guard let descriptor = item.descriptor else {
            return CacheRecordPayload(
                recordId: item.id,
                group: cacheGroup,
                identity: item.id,
                title: item.title,
                icons: "",
                list: listLabel(for: item, preferred: list),
                section: section,
                rating: rating
            )
        }
        return cachePayload(from: descriptor, rating: rating, list: list, section: section)
    }

    static func cachePayload(
        from descriptor: DiverItemDescriptor,
        rating: Double = 1,
        list: String? = nil,
        section: String = defaultSection
    ) -> CacheRecordPayload {
        CacheRecordPayload(
            recordId: descriptor.id,
            group: cacheGroup,
            identity: descriptor.id,
            title: descriptor.title,
            icons: "",
            list: descriptor.preferredListLabel(preferred: list),
            section: section,
            rating: rating
        )
    }

    static func cachedRecord(from payload: CacheRecordPayload) -> UserCachedRecord {
        UserCachedRecord(
            recordId: payload.recordId,
            group: payload.group,
            identity: payload.identity,
            title: payload.title,
            icons: payload.icons,
            list: payload.list,
            section: payload.section,
            rating: payload.rating
        )
    }

    private static func listLabel(for item: Item, preferred: String?) -> String {
        let resolvedPreferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !resolvedPreferred.isEmpty {
            return resolvedPreferred
        }

        let category = item.categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let category {
            return category
        }

        let styleTag = item.styleTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let styleTag {
            return styleTag
        }

        return DiverListLabel.default
    }
}

@MainActor
final class KnowMapsRetrievalAdapter: KnowledgeGraphRetrievalService {
    private let container: KnowMapsServiceContainer
    
    init(container: KnowMapsServiceContainer) {
        self.container = container
    }
    
    func retrieveRelevantContext(for query: String) async throws -> [(text: String, weight: Double)] {
        var context: [(text: String, weight: Double)] = []
        
        // 1. Check cached tastes for relevance
        let tastes = container.cacheManager.cachedTasteResults
        let relevantTastes = tastes.filter { result in
            query.localizedCaseInsensitiveContains(result.parentCategory) ||
            result.parentCategory.localizedCaseInsensitiveContains(query)
        }
        
        if !relevantTastes.isEmpty {
            let tasteNames = relevantTastes.map { $0.parentCategory }.joined(separator: ", ")
            context.append(("User matches tastes: \(tasteNames)", 1.0))
        }
        
        // 2. Check cached industry/category results
        let categories = container.cacheManager.cachedIndustryResults
        let relevantCategories = categories.filter { result in
            query.localizedCaseInsensitiveContains(result.parentCategory) ||
            result.parentCategory.localizedCaseInsensitiveContains(query)
        }
        
        if !relevantCategories.isEmpty {
            let catNames = relevantCategories.map { $0.parentCategory }.joined(separator: ", ")
            context.append(("User has interest in categories: \(catNames)", 1.0))
        }

        // 3. Search saved Diver items (ProcessedItems) and Boosted Concepts
        if let savedItemsInfo = try? retrieveSavedItems(for: query) {
            context.append(contentsOf: savedItemsInfo)
        }
        
        return context
    }

    private func retrieveSavedItems(for query: String) throws -> [(text: String, weight: Double)]? {
        guard let manager = UnifiedDataManager.shared else { return nil }
        var results: [(text: String, weight: Double)] = []
        
        // Fetch high-weight concepts to boost search
        let conceptDescriptor = FetchDescriptor<UserConcept>(
            predicate: #Predicate<UserConcept> { $0.weight > 1.2 },
            sortBy: [SortDescriptor(\.weight, order: .reverse)]
        )
        let boostedConcepts = try manager.mainContext.fetch(conceptDescriptor)
        
        for concept in boostedConcepts.prefix(5) {
             results.append(("User strongly values concept: \(concept.name)", concept.weight))
        }
        
        // Simple search on title or summary
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate<ProcessedItem> { item in
                (item.title?.localizedStandardContains(query) == true) ||
                (item.summary?.localizedStandardContains(query) == true)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Limit to recent/top 5 matches
        var fetchDescriptor = descriptor
        fetchDescriptor.fetchLimit = 5
        
        let items = try manager.mainContext.fetch(fetchDescriptor)
        
        if !items.isEmpty {
            let itemTitles = items.compactMap { $0.title }.joined(separator: ", ")
            results.append(("User has saved related items: \(itemTitles)", 1.0))
        }
        
        return results.isEmpty ? nil : results
    }
}

@MainActor
final class KnowMapsIndexingAdapter: KnowledgeGraphIndexingService {
    private let container: KnowMapsServiceContainer
    
    init(container: KnowMapsServiceContainer) {
        self.container = container
    }
    
    func indexItem(_ item: DiverKit.Item) async throws {
        // Stub: This overload is not currently used by the LocalPipelineService.
        // We index via DiverItemDescriptor.
    }
    
    func indexItem(_ descriptor: DiverItemDescriptor) async throws {
        try await container.cacheStore.store(descriptor: descriptor)
    }
}
@MainActor
final class KnowMapsUnifiedAdapter: KnowledgeGraphRetrievalService, KnowledgeGraphIndexingService {
    private let container: KnowMapsServiceContainer
    private let retrievalAdapter: KnowMapsRetrievalAdapter
    private let indexingAdapter: KnowMapsIndexingAdapter
    
    init(container: KnowMapsServiceContainer) {
        self.container = container
        self.retrievalAdapter = KnowMapsRetrievalAdapter(container: container)
        self.indexingAdapter = KnowMapsIndexingAdapter(container: container)
    }
    
    // MARK: - Retrieval
    func retrieveRelevantContext(for query: String) async throws -> [(text: String, weight: Double)] {
        try await retrievalAdapter.retrieveRelevantContext(for: query)
    }
    
    // MARK: - Indexing
    func indexItem(_ item: DiverKit.Item) async throws {
        try await indexingAdapter.indexItem(item)
    }
    
    func indexItem(_ descriptor: DiverItemDescriptor) async throws {
        try await indexingAdapter.indexItem(descriptor)
    }
}
