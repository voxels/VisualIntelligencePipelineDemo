//
//  DurabilityScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Standalone durability scoring strategy. Evaluates product longevity, repairability,
/// and material quality based on available data. Separate from quality/review scoring
/// per user requirement — durability is its own axis of evaluation.
public final class DurabilityScoringStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "durability"
    public let displayName = "Durability"
    
    public init() {}
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        var dimensions: [ScoringDimension] = []
        
        // Dimension 1: Category longevity baseline
        // Different product categories have different expected lifespans
        let categoryLongevity = categoryDurabilityBaseline(product.category)
        dimensions.append(ScoringDimension(
            name: "Category Longevity",
            score: categoryLongevity.score,
            weight: 0.3,
            source: "Category Analysis",
            explanation: categoryLongevity.explanation
        ))
        
        // Dimension 2: Brand reputation for durability
        // Known durable vs disposable brands (from enrichment or defaults)
        let brandDurability = brandDurabilityScore(product.brand)
        dimensions.append(ScoringDimension(
            name: "Brand Durability",
            score: brandDurability.score,
            weight: 0.3,
            source: "Brand Analysis",
            explanation: brandDurability.explanation
        ))
        
        // Dimension 3: Repairability index
        // EU repairability scoring framework (future: scrape iFixit, EU database)
        let repairability = repairabilityScore(product.category)
        dimensions.append(ScoringDimension(
            name: "Repairability",
            score: repairability.score,
            weight: 0.2,
            source: "Category Heuristic",
            explanation: repairability.explanation
        ))
        
        // Dimension 4: Material quality signals
        // Inferred from price point and category
        let materialScore: Float = 0.5 // Phase 2: derive from product specs
        dimensions.append(ScoringDimension(
            name: "Material Quality",
            score: materialScore,
            weight: 0.2,
            source: "Estimated",
            explanation: "Material data not yet available — estimated from category"
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
        return options.sorted { a, b in
            let aScore = a.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            let bScore = b.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            return aScore > bScore
        }
    }
    
    // MARK: - Category Heuristics
    
    private struct DimensionResult {
        let score: Float
        let explanation: String
    }
    
    private func categoryDurabilityBaseline(_ category: String) -> DimensionResult {
        let cat = category.lowercased()
        // Expected product lifespan by category → score
        switch cat {
        case let c where c.contains("electronics"):
            return DimensionResult(score: 0.4, explanation: "Electronics: 2-5 year typical lifespan")
        case let c where c.contains("clothing"):
            return DimensionResult(score: 0.3, explanation: "Clothing: varies widely by quality tier")
        case let c where c.contains("food"), let c where c.contains("beverage"):
            return DimensionResult(score: 0.1, explanation: "Consumable: single-use product")
        case let c where c.contains("furniture"):
            return DimensionResult(score: 0.8, explanation: "Furniture: 10-20 year expected lifespan")
        case let c where c.contains("automotive"):
            return DimensionResult(score: 0.7, explanation: "Automotive: 8-15 year expected lifespan")
        case let c where c.contains("tool"):
            return DimensionResult(score: 0.8, explanation: "Tools: 10+ year expected lifespan")
        default:
            return DimensionResult(score: 0.5, explanation: "Average category durability")
        }
    }
    
    private func brandDurabilityScore(_ brand: String?) -> DimensionResult {
        guard let brand else {
            return DimensionResult(score: 0.5, explanation: "Unknown brand — cannot assess durability reputation")
        }
        // Phase 2: lookup from durability database
        // For now, neutral score with brand name
        return DimensionResult(score: 0.5, explanation: "\(brand) — durability data not yet indexed")
    }
    
    private func repairabilityScore(_ category: String) -> DimensionResult {
        let cat = category.lowercased()
        // EU-style repairability index by category
        switch cat {
        case let c where c.contains("electronics"):
            return DimensionResult(score: 0.4, explanation: "Electronics: moderate repairability")
        case let c where c.contains("clothing"):
            return DimensionResult(score: 0.6, explanation: "Clothing: generally repairable")
        case let c where c.contains("furniture"):
            return DimensionResult(score: 0.7, explanation: "Furniture: highly repairable")
        case let c where c.contains("automotive"):
            return DimensionResult(score: 0.6, explanation: "Automotive: parts widely available")
        default:
            return DimensionResult(score: 0.5, explanation: "Average repairability for category")
        }
    }
}
