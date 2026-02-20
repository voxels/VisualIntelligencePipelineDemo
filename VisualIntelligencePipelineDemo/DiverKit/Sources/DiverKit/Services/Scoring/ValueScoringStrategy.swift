//
//  ValueScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Scoring strategy based on price-per-unit value and historical pricing trends.
/// Evaluates whether the current price represents good value relative to
/// historical data and comparable products.
public final class ValueScoringStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "value"
    public let displayName = "Value"
    
    public init() {}
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        // Value scoring uses PriceTrajectory if available
        let trajectory = enrichment as? PriceTrajectory
        var dimensions: [ScoringDimension] = []
        
        // Dimension 1: Price trend direction
        if let trend = trajectory {
            let trendScore: Float
            let explanation: String
            switch trend.projectedDirection {
            case .falling:
                trendScore = 0.3 // Wait — prices dropping
                explanation = "Prices trending down (\(trend.horizonDays)-day outlook)"
            case .stable:
                trendScore = 0.6 // Neutral
                explanation = "Prices stable (\(trend.horizonDays)-day outlook)"
            case .rising:
                trendScore = 0.9 // Buy now — prices going up
                explanation = "Prices trending up — buy now saves money"
            }
            dimensions.append(ScoringDimension(
                name: "Price Trend",
                score: trendScore,
                weight: 0.4,
                source: "Price Analysis",
                explanation: explanation
            ))
            
            // Dimension 2: Trend confidence
            let confidenceScore = trend.confidenceInterval
            dimensions.append(ScoringDimension(
                name: "Forecast Confidence",
                score: confidenceScore,
                weight: 0.2,
                source: "Price Analysis",
                explanation: "\(Int(confidenceScore * 100))% confidence in projection"
            ))
        } else {
            // No price data — neutral score
            dimensions.append(ScoringDimension(
                name: "Price Trend",
                score: 0.5,
                weight: 0.4,
                source: "none",
                explanation: "No historical pricing available"
            ))
        }
        
        // Dimension 3: Price positioning (comparing to category average — placeholder)
        // In Phase 2, this would compare against scraped platform prices
        dimensions.append(ScoringDimension(
            name: "Price Position",
            score: 0.5,
            weight: 0.4,
            source: "Price Analysis",
            explanation: "Price comparison data not yet available"
        ))
        
        let totalWeight = dimensions.reduce(0) { $0 + $1.weight }
        let overallScore = totalWeight > 0
            ? dimensions.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
            : 0.5
        
        return ProductScore(
            strategyID: strategyID,
            overallScore: overallScore,
            dimensions: dimensions
        )
    }
    
    public func rank(_ options: [PurchaseOption]) async throws -> [PurchaseOption] {
        // Sort by value score, then by lowest price
        return options.sorted { a, b in
            let aScore = a.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            let bScore = b.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            if aScore != bScore { return aScore > bScore }
            return a.price < b.price
        }
    }
}
