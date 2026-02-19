//
//  CommerceTypes.swift
//  DiverShared
//
//  Created by Antigravity on 02/19/26.
//

import Foundation

// MARK: - Product Identification

/// A classified product identified via barcode scan, visual detection, or entity resolution.
public struct ProductClassification: Codable, Sendable, Hashable {
    public let productID: String
    public let name: String
    public let category: String
    public let brand: String?
    public let barcode: String?
    public let confidence: Float
    
    public init(productID: String, name: String, category: String, brand: String? = nil, barcode: String? = nil, confidence: Float) {
        self.productID = productID
        self.name = name
        self.category = category
        self.brand = brand
        self.barcode = barcode
        self.confidence = confidence
    }
}

// MARK: - Modular Scoring

/// A strategy-agnostic product score. Each scoring strategy produces one of these.
public struct ProductScore: Codable, Sendable, Hashable {
    public let strategyID: String
    public let overallScore: Float  // 0.0 (worst) – 1.0 (best)
    public let dimensions: [ScoringDimension]
    
    public init(strategyID: String, overallScore: Float, dimensions: [ScoringDimension]) {
        self.strategyID = strategyID
        self.overallScore = overallScore
        self.dimensions = dimensions
    }
}

/// A single dimension within a scoring strategy (e.g., "Carbon Intensity", "Certification Quality").
public struct ScoringDimension: Codable, Sendable, Hashable {
    public let name: String
    public let score: Float         // 0.0 – 1.0
    public let weight: Float        // Relative importance within this strategy
    public let source: String       // Data source (e.g., "Climate TRACE", "Open Food Facts")
    public let explanation: String  // Human-readable rationale
    
    public init(name: String, score: Float, weight: Float, source: String, explanation: String) {
        self.name = name
        self.score = score
        self.weight = weight
        self.source = source
        self.explanation = explanation
    }
}

// MARK: - Economic Trends

/// A price trajectory projection from the nowcasting engine.
public struct PriceTrajectory: Codable, Sendable {
    public let commodityID: String
    public let dataPoints: [PriceDataPoint]
    public let projectedDirection: TrendDirection
    public let confidenceInterval: Float  // 0.0 – 1.0
    public let horizonDays: Int           // Projection window (e.g., 14)
    
    public init(commodityID: String, dataPoints: [PriceDataPoint], projectedDirection: TrendDirection, confidenceInterval: Float, horizonDays: Int) {
        self.commodityID = commodityID
        self.dataPoints = dataPoints
        self.projectedDirection = projectedDirection
        self.confidenceInterval = confidenceInterval
        self.horizonDays = horizonDays
    }
}

/// A single data point in a price time series.
public struct PriceDataPoint: Codable, Sendable {
    public let date: Date
    public let value: Decimal
    public let isProjected: Bool
    
    public init(date: Date, value: Decimal, isProjected: Bool = false) {
        self.date = date
        self.value = value
        self.isProjected = isProjected
    }
}

/// Direction of a price trend.
public enum TrendDirection: String, Codable, Sendable {
    case rising
    case falling
    case stable
}

// MARK: - Commerce Routing

/// User's ethical filtering preferences for ranking commerce platforms.
public struct EthicalPolicy: Codable, Sendable {
    /// Maximum acceptable carbon footprint score (0.0 = strictest, 1.0 = no filter).
    public let carbonThreshold: Float
    /// Preferred certification types (e.g., "Fair Trade", "B Corp", "Organic").
    public let preferredCertifications: [String]
    /// Platform names ranked by user preference (first = most preferred).
    public let platformRanking: [String]
    /// Whether to exclude platforms with known labor violations.
    public let excludeLaborViolations: Bool
    
    public init(
        carbonThreshold: Float = 0.5,
        preferredCertifications: [String] = [],
        platformRanking: [String] = [],
        excludeLaborViolations: Bool = false
    ) {
        self.carbonThreshold = carbonThreshold
        self.preferredCertifications = preferredCertifications
        self.platformRanking = platformRanking
        self.excludeLaborViolations = excludeLaborViolations
    }
}

/// A ranked commerce platform result from CommerceRouting.
public struct PlatformMatch: Codable, Sendable, Identifiable {
    public var id: String { platform }
    public let platform: String             // e.g., "amazon", "target", "bestbuy"
    public let ethicalMatchScore: Float     // 0.0 – 1.0
    public let affiliateURL: URL?
    public let matchReasons: [String]       // e.g., ["B Corp certified", "Low carbon"]
    
    public init(
        platform: String,
        ethicalMatchScore: Float,
        affiliateURL: URL? = nil,
        matchReasons: [String] = []
    ) {
        self.platform = platform
        self.ethicalMatchScore = ethicalMatchScore
        self.affiliateURL = affiliateURL
        self.matchReasons = matchReasons
    }
}

// MARK: - Commerce Output

/// A purchase option from a third-party platform.
public struct PurchaseOption: Codable, Sendable, Identifiable {
    public let id: String
    public let platform: String         // "amazon", "ebay", "thrive_market"
    public let productName: String
    public let brand: String?
    public let price: Decimal
    public let currency: String
    public let scores: [ProductScore]
    public let affiliateURL: URL
    
    public init(id: String = UUID().uuidString, platform: String, productName: String, brand: String? = nil, price: Decimal, currency: String = "USD", scores: [ProductScore] = [], affiliateURL: URL) {
        self.id = id
        self.platform = platform
        self.productName = productName
        self.brand = brand
        self.price = price
        self.currency = currency
        self.scores = scores
        self.affiliateURL = affiliateURL
    }
}

/// A ranked recommendation combining scoring, brand affinity, and economic trends.
public struct RankedRecommendation: Codable, Sendable, Identifiable {
    public let id: String
    public let option: PurchaseOption
    public let brandAffinity: Float     // 0.0 – 1.0, from UserConcept weight
    public let compositeScore: Float    // strategy × brand × trend
    
    public init(id: String = UUID().uuidString, option: PurchaseOption, brandAffinity: Float, compositeScore: Float) {
        self.id = id
        self.option = option
        self.brandAffinity = brandAffinity
        self.compositeScore = compositeScore
    }
}

// MARK: - ESG Data (Default Scoring Strategy Input)

/// ESG enrichment data from external APIs (Climate TRACE, Open Food Facts, etc.).
/// This is the input to `ESGScoringStrategy`, NOT an SLM-generated type.
public struct ESGEnrichment: Codable, Sendable {
    // ── Numerical Scores ──
    public let carbonIntensity: Float?      // kg CO₂e per revenue unit
    public let dataQualityTier: Int         // 1 (verified) – 5 (sector average), PCAF-adapted
    public let certifications: [String]     // ["Carbon Trust", "EPD"]
    public let ecoScore: String?            // Open Food Facts Eco-Score (A-E)
    public let source: String               // "Open Food Facts", "Open Beauty Facts", etc.
    public let retrievedAt: Date
    
    // ── Rich Text Context (persisted for SLM summaries) ──
    public let ingredientsText: String?     // Full ingredient list
    public let allergens: [String]          // ["milk", "soy", "gluten"]
    public let traces: [String]             // ["nuts", "peanuts"] — "may contain"
    public let origins: String?             // Country/region of origin
    public let manufacturingPlaces: String? // Where it's made
    public let novaGroup: Int?              // NOVA ultra-processing: 1 (unprocessed) – 4 (ultra-processed)
    public let nutriScore: String?          // Nutri-Score grade (A-E)
    public let nutriments: [String: Float]  // Nutrition facts: ["energy_kcal": 250, "sugars": 12, ...]
    public let packagingText: String?       // Packaging materials description
    public let quantity: String?            // Package size (for shrinkflation tracking)
    public let genericName: String?         // Generic product description
    public let countriesSold: [String]      // Countries where sold
    public let stores: [String]             // Retail availability
    
    public init(
        carbonIntensity: Float? = nil,
        dataQualityTier: Int,
        certifications: [String] = [],
        ecoScore: String? = nil,
        source: String,
        retrievedAt: Date = Date(),
        ingredientsText: String? = nil,
        allergens: [String] = [],
        traces: [String] = [],
        origins: String? = nil,
        manufacturingPlaces: String? = nil,
        novaGroup: Int? = nil,
        nutriScore: String? = nil,
        nutriments: [String: Float] = [:],
        packagingText: String? = nil,
        quantity: String? = nil,
        genericName: String? = nil,
        countriesSold: [String] = [],
        stores: [String] = []
    ) {
        self.carbonIntensity = carbonIntensity
        self.dataQualityTier = dataQualityTier
        self.certifications = certifications
        self.ecoScore = ecoScore
        self.source = source
        self.retrievedAt = retrievedAt
        self.ingredientsText = ingredientsText
        self.allergens = allergens
        self.traces = traces
        self.origins = origins
        self.manufacturingPlaces = manufacturingPlaces
        self.novaGroup = novaGroup
        self.nutriScore = nutriScore
        self.nutriments = nutriments
        self.packagingText = packagingText
        self.quantity = quantity
        self.genericName = genericName
        self.countriesSold = countriesSold
        self.stores = stores
    }
    
    /// Builds a text summary of all available context for SLM consumption.
    /// Only includes fields that have data — no empty placeholders.
    public var contextSummary: String {
        var parts: [String] = []
        if let name = genericName { parts.append("Product: \(name)") }
        if let qty = quantity { parts.append("Size: \(qty)") }
        if let ingredients = ingredientsText { parts.append("Ingredients: \(ingredients)") }
        if !allergens.isEmpty { parts.append("Allergens: \(allergens.joined(separator: ", "))") }
        if !traces.isEmpty { parts.append("May contain: \(traces.joined(separator: ", "))") }
        if let nova = novaGroup { parts.append("NOVA processing level: \(nova)/4") }
        if let ns = nutriScore { parts.append("Nutri-Score: \(ns.uppercased())") }
        if let eco = ecoScore { parts.append("Eco-Score: \(eco.uppercased())") }
        if let carbon = carbonIntensity { parts.append(String(format: "Carbon: %.1f kg CO₂e", carbon)) }
        if !certifications.isEmpty { parts.append("Certifications: \(certifications.joined(separator: ", "))") }
        if let origin = origins { parts.append("Origin: \(origin)") }
        if let mfg = manufacturingPlaces { parts.append("Made in: \(mfg)") }
        if let packaging = packagingText { parts.append("Packaging: \(packaging)") }
        if !nutriments.isEmpty {
            let top = nutriments.sorted { $0.key < $1.key }.prefix(8)
                .map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            parts.append("Nutrition: \(top)")
        }
        if !countriesSold.isEmpty { parts.append("Sold in: \(countriesSold.joined(separator: ", "))") }
        if !stores.isEmpty { parts.append("Available at: \(stores.joined(separator: ", "))") }
        parts.append("Source: \(source), Tier \(dataQualityTier)")
        return parts.joined(separator: "\n")
    }
}

// MARK: - Brand

/// A brand profile extracted from user activity, used in RAG ranking.
public struct BrandProfile: Codable, Sendable, Hashable {
    public let name: String
    public let category: String?
    public let userAffinity: Float  // 0.0 – 1.0, derived from UserConcept weight
    public let productCount: Int    // Times encountered in captures
    
    public init(name: String, category: String? = nil, userAffinity: Float = 0.0, productCount: Int = 0) {
        self.name = name
        self.category = category
        self.userAffinity = userAffinity
        self.productCount = productCount
    }
}

// MARK: - Ownership & Purchase Tracking

/// Tracks the user's relationship with a product — from scan to ownership.
/// Created when a user scans a product tag to add it to their personal collection,
/// or when a purchase CTA is tapped. Closes the RAG feedback loop by recording
/// whether recommendations led to actual purchases.
public struct PurchaseOutcome: Codable, Sendable, Identifiable {
    public let id: String
    public let productID: String           // Links to ProductClassification.productID
    public let brand: String?
    public let category: String?
    public let status: OwnershipStatus
    public let source: OutcomeSource       // How we learned about this
    public let scoringContext: [String]     // Strategy IDs active at recommendation time
    public let recommendedCompositeScore: Float? // Score when recommended (for RAG validation)
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        productID: String,
        brand: String? = nil,
        category: String? = nil,
        status: OwnershipStatus = .owned,
        source: OutcomeSource = .tagScan,
        scoringContext: [String] = [],
        recommendedCompositeScore: Float? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.productID = productID
        self.brand = brand
        self.category = category
        self.status = status
        self.source = source
        self.scoringContext = scoringContext
        self.recommendedCompositeScore = recommendedCompositeScore
        self.createdAt = createdAt
    }
}

/// The user's ownership relationship with a product.
public enum OwnershipStatus: String, Codable, Sendable {
    case owned          // User has this product (scanned tag / confirmed purchase)
    case considering    // CTA tapped but not confirmed
    case returned       // User had it but returned
    case wishlisted     // User wants it but hasn't bought yet
}

/// How we learned about the purchase/ownership.
public enum OutcomeSource: String, Codable, Sendable {
    case tagScan        // User scanned product barcode/tag to add to collection
    case ctaTap         // User tapped "Buy" CTA from recommendation
    case financeKit     // Matched via FinanceKit transaction data
    case manual         // User manually marked as owned
    case shared         // User shared this product with a contact (strongest endorsement)
}

// MARK: - Score History

/// A single strategy's score at a point in time — lightweight for chart data.
public struct StrategyScoreEntry: Codable, Sendable, Identifiable {
    public var id: String { strategyID }
    public let strategyID: String
    public let displayName: String
    public let score: Float
    
    public init(strategyID: String, displayName: String, score: Float) {
        self.strategyID = strategyID
        self.displayName = displayName
        self.score = score
    }
}
