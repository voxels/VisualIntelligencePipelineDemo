@testable import Diver
import Security
import SwiftData
import Testing
import knowmaps

struct KnowMapsServiceContainerTests {
    @Test @MainActor
    func containerBuildsWithInMemoryStore() throws {
        guard hasCloudKitEntitlement() else {
            return
        }

        let schema = Schema([
            UserCachedRecord.self,
            RecommendationData.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let mainContainer = try ModelContainer(for: schema, configurations: [configuration])
        let container = KnowMapsServiceContainer(
            container: mainContainer,
            analyticsService: TestAnalyticsService()
        )

        #expect(
            container.initializationError == nil,
            "Expected no initialization error, got \(String(describing: container.initializationError))."
        )
        let resolvedCacheManager = container.modelController.cacheManager as? CloudCacheManager
        #expect(resolvedCacheManager != nil, "Expected model controller to use CloudCacheManager.")
        #expect(resolvedCacheManager === container.cacheManager, "Expected cache managers to match.")
    }
}
