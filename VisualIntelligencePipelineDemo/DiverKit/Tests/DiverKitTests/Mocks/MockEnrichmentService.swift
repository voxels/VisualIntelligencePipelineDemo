import Foundation
import CoreLocation
@testable import DiverKit

/// A configurable mock implementation of `ContextualEnrichmentService` for testing.
/// Returns pre-set results and tracks call counts for verification.
public final class MockEnrichmentService: ContextualEnrichmentService, @unchecked Sendable {
    
    // MARK: - Configurable Results
    
    /// Result to return from `enrich(location:)`. Set to nil to simulate "no enrichment found".
    public var locationResult: EnrichmentData?
    
    /// Result to return from `enrich(query:location:)`.
    public var queryResult: EnrichmentData?
    
    /// Results to return from `searchNearby(location:limit:)`.
    public var nearbyResults: [EnrichmentData] = []
    
    /// Results to return from `search(query:location:limit:)`.
    public var searchResults: [EnrichmentData] = []
    
    /// Result to return from `fetchDetails(for:)`.
    public var detailsResult: EnrichmentData?
    
    /// Error to throw from any method. If set, overrides the result.
    public var errorToThrow: Error?
    
    // MARK: - Call Tracking
    
    public private(set) var enrichLocationCallCount = 0
    public private(set) var enrichQueryCallCount = 0
    public private(set) var searchNearbyCallCount = 0
    public private(set) var searchCallCount = 0
    public private(set) var fetchDetailsCallCount = 0
    
    public private(set) var lastEnrichedLocation: CLLocationCoordinate2D?
    public private(set) var lastEnrichedQuery: String?
    
    public init() {}
    
    // MARK: - ContextualEnrichmentService
    
    public func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        enrichLocationCallCount += 1
        lastEnrichedLocation = location
        if let error = errorToThrow { throw error }
        return locationResult
    }
    
    public func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        enrichQueryCallCount += 1
        lastEnrichedQuery = query
        if let error = errorToThrow { throw error }
        return queryResult
    }
    
    public func searchNearby(location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        searchNearbyCallCount += 1
        lastEnrichedLocation = location
        if let error = errorToThrow { throw error }
        return nearbyResults
    }
    
    public func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        searchCallCount += 1
        lastEnrichedQuery = query
        if let error = errorToThrow { throw error }
        return searchResults
    }
    
    public func fetchDetails(for id: String) async throws -> EnrichmentData? {
        fetchDetailsCallCount += 1
        if let error = errorToThrow { throw error }
        return detailsResult
    }
    
    /// Resets all call counts and last-captured arguments.
    public func reset() {
        enrichLocationCallCount = 0
        enrichQueryCallCount = 0
        searchNearbyCallCount = 0
        searchCallCount = 0
        fetchDetailsCallCount = 0
        lastEnrichedLocation = nil
        lastEnrichedQuery = nil
    }
}

/// A configurable mock implementation of `LinkEnrichmentService` for testing.
public final class MockLinkEnrichmentService: LinkEnrichmentService, @unchecked Sendable {
    
    public var result: EnrichmentData?
    public var errorToThrow: Error?
    public private(set) var enrichCallCount = 0
    public private(set) var lastEnrichedURL: URL?
    
    public init() {}
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        enrichCallCount += 1
        lastEnrichedURL = url
        if let error = errorToThrow { throw error }
        return result
    }
    
    public func reset() {
        enrichCallCount = 0
        lastEnrichedURL = nil
    }
}
