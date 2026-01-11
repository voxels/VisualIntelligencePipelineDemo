import Foundation
import DiverShared

/// A service that combines multiple enrichment services, trying each until one succeeds.
public final class CompositeLinkEnrichmentService: LinkEnrichmentService {
    private let services: [LinkEnrichmentService]
    
    public init(services: [LinkEnrichmentService]) {
        self.services = services
    }
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        for service in services {
            if let data = try? await service.enrich(url: url) {
                return data
            }
        }
        return nil
    }
}
