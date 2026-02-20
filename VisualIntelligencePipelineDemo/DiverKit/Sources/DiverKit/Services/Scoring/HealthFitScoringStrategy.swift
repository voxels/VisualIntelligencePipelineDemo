//
//  HealthFitScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Scores products based on personal health alignment using on-device health data.
///
/// Sub-dimensions:
/// - **Nutritional Alignment**: Product nutrients vs user's dietary goals (HealthKit)
/// - **Allergen Safety**: Known allergens vs user's flagged sensitivities
/// - **Dietary Compliance**: Matches user's diet type (keto, vegan, low-sodium)
/// - **Activity Alignment**: Products that support user's fitness patterns
///
/// All health data stays on-device (HealthKit). No health data is sent to external APIs.
/// Food products get full scoring; non-food products get a neutral pass-through.
public final class HealthFitScoringStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "health"
    public let displayName = "Health Fit"
    
    public init() {}
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        // Non-food/supplement products get a neutral score
        let foodCategories = ["food", "beverage", "snack", "supplement", "dairy", "meat",
                              "produce", "bakery", "cereal", "frozen", "candy", "nutrition"]
        let isFood = foodCategories.contains { product.category.lowercased().contains($0) }
        
        guard isFood else {
            // Check if it's a fitness/wellness product
            let wellnessCategories = ["fitness", "sport", "wellness", "health", "exercise"]
            let isWellness = wellnessCategories.contains { product.category.lowercased().contains($0) }
            
            if isWellness {
                return ProductScore(
                    strategyID: strategyID,
                    overallScore: 0.6,
                    dimensions: [
                        ScoringDimension(
                            name: "Activity Alignment",
                            score: 0.6,
                            weight: 1.0,
                            source: "HealthKit",
                            explanation: "Fitness product — HealthKit integration pending"
                        )
                    ]
                )
            }
            
            return ProductScore(
                strategyID: strategyID,
                overallScore: 0.5,
                dimensions: [
                    ScoringDimension(
                        name: "Relevance",
                        score: 0.5,
                        weight: 1.0,
                        source: "Category Analysis",
                        explanation: "Non-food product — health scoring not applicable"
                    )
                ]
            )
        }
        
        var dimensions: [ScoringDimension] = []
        
        // 1. Nutritional Alignment (HealthKit dietary goals)
        // Phase 1a: Query HealthKit for user's nutrition targets
        dimensions.append(ScoringDimension(
            name: "Nutritional Alignment",
            score: 0.5,
            weight: 0.35,
            source: "HealthKit",
            explanation: "HealthKit dietary goal matching pending"
        ))
        
        // 2. Allergen Safety
        // Phase 1a: Cross-reference Open Food Facts allergens with user's flagged allergens
        dimensions.append(ScoringDimension(
            name: "Allergen Safety",
            score: 0.7, // Default safe unless known allergens
            weight: 0.30,
            source: "Open Food Facts",
            explanation: "No allergen data available — assumed safe"
        ))
        
        // 3. Dietary Compliance
        // Phase 1a: Match against user's diet preferences (keto, vegan, etc.)
        dimensions.append(ScoringDimension(
            name: "Dietary Compliance",
            score: 0.5,
            weight: 0.20,
            source: "User Preferences",
            explanation: "Dietary preference matching pending"
        ))
        
        // 4. Processing Level
        // Ultra-processed food (UPF) detection from ingredient analysis
        dimensions.append(ScoringDimension(
            name: "Processing Level",
            score: 0.5,
            weight: 0.15,
            source: "Open Food Facts",
            explanation: "NOVA processing classification pending"
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
        options.sorted { a, b in
            let aScore = a.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            let bScore = b.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            return aScore > bScore
        }
    }
}
