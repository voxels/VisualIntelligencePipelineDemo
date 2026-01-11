import Foundation
import SwiftData
import Testing
import knowmaps
@testable import Diver

struct KnowMapsCacheStoreTests {
    @Test @MainActor
    func storeAndFetchCachedRecords() async throws {
        guard hasCloudKitEntitlement() else {
            return
        }

        let schema = Schema([
            UserCachedRecord.self,
            RecommendationData.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let container = KnowMapsServiceContainer(
            container: modelContainer,
            analyticsService: TestAnalyticsService()
        )
        let store = KnowMapsCacheStore(cacheService: container.cacheService)

        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(url: url, title: "Example Place", categories: ["coffee"])

        let stored = try await store.store(item: item, rating: 2)
        #expect(stored == true)

        let records = try await store.fetchCachedRecords()
        #expect(records.count == 1)

        let payload = try payloadDictionary(for: records[0])
        #expect(payload["recordId"] as? String == item.id)
        #expect(payload["identity"] as? String == item.id)
        #expect(payload["group"] as? String == KnowMapsAdapter.cacheGroup)
        #expect(payload["list"] as? String == "coffee")
        #expect(payload["section"] as? String == KnowMapsAdapter.defaultSection)
        #expect(payload["rating"] as? Double == 2)
    }

    private enum PayloadError: Error {
        case invalidPayload
    }

    private func payloadDictionary(for record: UserCachedRecord) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw PayloadError.invalidPayload
        }
        return payload
    }
}
