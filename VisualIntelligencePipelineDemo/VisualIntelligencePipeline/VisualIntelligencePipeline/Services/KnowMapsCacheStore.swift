import Foundation
import knowmaps
import DiverShared

@MainActor
final class KnowMapsCacheStore {
    private let cacheService: CloudCacheService

    init(cacheService: CloudCacheService) {
        self.cacheService = cacheService
    }

    @discardableResult
    func store(
        item: Item,
        rating: Double = 1,
        list: String? = nil,
        section: String = KnowMapsAdapter.defaultSection
    ) async throws -> Bool {
        let payload = KnowMapsAdapter.cachePayload(
            from: item,
            rating: rating,
            list: list,
            section: section
        )
        return try await cacheService.storeUserCachedRecord(
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

    @discardableResult
    func store(
        descriptor: DiverItemDescriptor,
        rating: Double = 1,
        list: String? = nil,
        section: String = KnowMapsAdapter.defaultSection
    ) async throws -> Bool {
        let payload = KnowMapsAdapter.cachePayload(
            from: descriptor,
            rating: rating,
            list: list,
            section: section
        )
        return try await cacheService.storeUserCachedRecord(
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

    func fetchCachedRecords() async throws -> [SendableCachedRecord] {
        try await cacheService.fetchGroupedUserCachedRecords(for: KnowMapsAdapter.cacheGroup)
    }
}
