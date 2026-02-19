//
//  ProductScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// A pluggable product scoring strategy. Different strategies can rank products
/// by different criteria (ESG, quality, value, brand alignment, etc.).
///
/// The default implementation is `ESGScoringStrategy`. Alternative strategies
/// can be registered and swapped at runtime via user preferences.
public protocol ProductScoringStrategy: Sendable {
    /// Unique identifier for this strategy (e.g., "esg", "quality", "value")
    var strategyID: String { get }
    
    /// Display name shown in UI (e.g., "Sustainability", "Quality", "Best Value")
    var displayName: String { get }
    
    /// Score a single product against this strategy's criteria.
    /// - Parameters:
    ///   - product: The classified product to score
    ///   - enrichment: Strategy-specific enrichment data (e.g., `ESGEnrichment` for ESG strategy)
    /// - Returns: A `ProductScore` with dimensional breakdown
    func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore
    
    /// Score and rank a list of purchase options, returning them sorted best-first.
    /// - Parameter options: Unranked purchase options from platform searches
    /// - Returns: Options sorted by this strategy's scoring, with scores populated
    func rank(_ options: [PurchaseOption]) async throws -> [PurchaseOption]
}

/// Protocol for services that search third-party platforms and recommend products
/// using a scoring strategy, user brand preferences, and preference-learned weights.
public protocol ProductRecommending: Sendable {
    /// Generate ranked recommendations for a detected product.
    /// - Parameters:
    ///   - product: The identified product (via barcode, visual detection, etc.)
    ///   - strategy: The active scoring strategy to evaluate options against
    ///   - brandAffinities: User brand preferences from knowledge graph
    ///   - priceTrend: Optional economic trend data for buy/wait signal
    ///   - strategyWeights: Per-strategy weights learned from owned product history
    /// - Returns: Ranked recommendations sorted by composite score
    func recommend(
        for product: ProductClassification,
        using strategy: any ProductScoringStrategy,
        brandAffinities: [BrandProfile],
        priceTrend: PriceTrajectory?,
        strategyWeights: [String: Float]
    ) async throws -> [RankedRecommendation]
}
