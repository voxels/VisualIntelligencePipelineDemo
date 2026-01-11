import Foundation
import CoreLocation
import DiverShared

/// Data structure for enriched link metadata
public struct EnrichmentData: Sendable, Codable {
    public var title: String?
    public var descriptionText: String?
    public var image: String?
    public var categories: [String]
    public var styleTags: [String]
    public let location: String?
    public let price: Double?
    public let rating: Double?
    public let questions: [String]
    
    // Extensible Contexts
    public let webContext: WebContext?
    public let documentContext: DocumentContext?
    public let placeContext: PlaceContext?
    public let qrContext: QRCodeContext?

    public init(
        title: String? = nil,
        descriptionText: String? = nil,
        image: String? = nil,
        categories: [String] = [],
        styleTags: [String] = [],
        location: String? = nil,
        price: Double? = nil,
        rating: Double? = nil,
        questions: [String] = [],
        webContext: WebContext? = nil,
        documentContext: DocumentContext? = nil,
        placeContext: PlaceContext? = nil,
        qrContext: QRCodeContext? = nil
    ) {
        self.title = title
        self.descriptionText = descriptionText
        self.image = image
        self.categories = categories
        self.styleTags = styleTags
        self.location = location
        self.price = price
        self.rating = rating
        self.questions = questions
        self.webContext = webContext
        self.documentContext = documentContext
        self.placeContext = placeContext
        self.qrContext = qrContext
    }
}

/// Protocol for services that can enrich a link with additional metadata
public protocol LinkEnrichmentService: Sendable {
    /// Enrich the given URL with additional metadata
    /// - Parameter url: The URL to enrich
    /// - Returns: Enrichment data if available, or nil if no enrichment could be performed
    func enrich(url: URL) async throws -> EnrichmentData?
}

/// Protocol for services that can enrich based on location and context
public protocol ContextualEnrichmentService: Sendable {
    /// Enrich based on a location
    /// - Parameter location: The GPS coordinates
    /// - Returns: Enrichment data if a place is found
    func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData?

    /// Enrich based on a query and optional location
    /// - Parameters:
    ///   - query: The search query (e.g. venue name)
    ///   - location: Optional GPS coordinates for proximity
    /// - Returns: Enrichment data if results are found
    func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData?

    /// Search for nearby places
    /// - Parameters:
    ///   - location: The GPS coordinates
    ///   - limit: Maximum number of results
    /// - Returns: List of candidate places
    func searchNearby(location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData]
    /// Search for places by query
    /// - Parameters:
    ///   - query: The search text
    ///   - location: The reference location
    ///   - limit: Maximum results
    /// - Returns: List of candidate places
    func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData]
}
