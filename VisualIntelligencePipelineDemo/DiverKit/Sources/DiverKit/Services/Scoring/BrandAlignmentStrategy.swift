//
//  BrandAlignmentStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Scoring strategy based on user brand affinity from the knowledge graph.
/// Scores products higher when they match brands the user frequently interacts with.
/// Brand affinity is derived from `UserConcept` entries with "Brand:" prefixed definitions.
public final class BrandAlignmentStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "brand"
    public let displayName = "Brand Fit"
    
    private let brandAffinities: [BrandProfile]
    
    public init(brandAffinities: [BrandProfile] = []) {
        self.brandAffinities = brandAffinities
    }
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        var dimensions: [ScoringDimension] = []
        
        // Dimension 1: Direct brand match
        let directMatch = brandAffinities.first {
            guard let brand = product.brand else { return false }
            return $0.name.caseInsensitiveCompare(brand) == .orderedSame
        }
        
        let matchScore: Float = directMatch?.userAffinity ?? 0.0
        dimensions.append(ScoringDimension(
            name: "Brand Match",
            score: matchScore,
            weight: 0.5,
            source: "User History",
            explanation: directMatch != nil
                ? "\(directMatch!.name) — \(directMatch!.productCount) interactions"
                : "No prior interaction with this brand"
        ))
        
        // Dimension 2: Category familiarity
        // How often the user interacts with brands in this product's category
        let categoryBrands = brandAffinities.filter {
            $0.category?.caseInsensitiveCompare(product.category) == .orderedSame
        }
        let categoryScore: Float = categoryBrands.isEmpty
            ? 0.2
            : min(1.0, Float(categoryBrands.count) * 0.2)
        dimensions.append(ScoringDimension(
            name: "Category Familiarity",
            score: categoryScore,
            weight: 0.3,
            source: "User History",
            explanation: "\(categoryBrands.count) known brands in \(product.category)"
        ))
        
        // Dimension 3: Brand popularity (based on total product count across all brands)
        let totalInteractions = brandAffinities.reduce(0) { $0 + $1.productCount }
        let popularityScore: Float = directMatch != nil && totalInteractions > 0
            ? min(1.0, Float(directMatch!.productCount) / Float(max(totalInteractions, 1)) * 3.0)
            : 0.1
        dimensions.append(ScoringDimension(
            name: "Brand Preference Strength",
            score: popularityScore,
            weight: 0.2,
            source: "User History",
            explanation: directMatch != nil
                ? "\(Int(popularityScore * 100))% of your brand interactions"
                : "New brand"
        ))
        
        let totalWeight = dimensions.reduce(0) { $0 + $1.weight }
        let overallScore = totalWeight > 0
            ? dimensions.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
            : 0.0
        
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
}
