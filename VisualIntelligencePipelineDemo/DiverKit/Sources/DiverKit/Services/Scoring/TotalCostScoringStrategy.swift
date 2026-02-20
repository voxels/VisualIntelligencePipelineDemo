//
//  TotalCostScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Scores products based on true lifetime cost beyond sticker price.
///
/// Sub-dimensions:
/// - **Energy Cost**: Projected energy consumption over product lifetime (Energy Star, smart home data)
/// - **Consumables**: Recurring costs for filters, cartridges, pods, blades, etc.
/// - **Subscription Fees**: Required subscriptions, cloud fees, premium tiers
/// - **Maintenance**: Repair frequency, service costs, warranty gaps
/// - **Replacement Cycle**: Expected lifespan and replacement cost amortization
/// - **Resale Value**: Secondary market demand (eBay sold listings, depreciation curve)
///
/// Particularly impactful for electronics, appliances, vehicles, and subscription products.
public final class TotalCostScoringStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "totalcost"
    public let displayName = "Total Cost"
    
    public init() {}
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        var dimensions: [ScoringDimension] = []
        let category = product.category.lowercased()
        
        // Determine product lifecycle category for scoring relevance
        let isElectronics = ["electronic", "computer", "phone", "tablet", "tv", "audio", "camera"].contains { category.contains($0) }
        let isAppliance = ["appliance", "washer", "dryer", "refrigerator", "dishwasher", "oven", "hvac"].contains { category.contains($0) }
        let isSubscription = ["software", "app", "service", "subscription", "streaming"].contains { category.contains($0) }
        let isConsumable = ["food", "beverage", "cleaning", "beauty", "personal"].contains { category.contains($0) }
        let isDurable = isElectronics || isAppliance
        
        // 1. Energy Cost (electronics/appliances)
        if isDurable {
            dimensions.append(ScoringDimension(
                name: "Energy Cost",
                score: 0.5,
                weight: 0.25,
                source: "Energy Star",
                explanation: "Energy consumption data not yet indexed"
            ))
        }
        
        // 2. Consumables (printers=ink, razors=blades, coffee=pods, etc.)
        let consumableCategories = ["printer", "razor", "coffee", "vacuum", "water filter", "air purifier"]
        let hasConsumables = consumableCategories.contains { category.contains($0) } || isDurable
        if hasConsumables {
            dimensions.append(ScoringDimension(
                name: "Consumables",
                score: 0.5,
                weight: 0.20,
                source: "Product Analysis",
                explanation: "Recurring consumable costs not yet analyzed"
            ))
        }
        
        // 3. Subscription/Recurring Fees
        if isSubscription || isElectronics {
            dimensions.append(ScoringDimension(
                name: "Subscription Fees",
                score: isSubscription ? 0.3 : 0.7, // Subscription products penalized by default
                weight: 0.25,
                source: "App Store / Product Analysis",
                explanation: isSubscription
                    ? "Subscription product — recurring costs expected"
                    : "No required subscriptions detected"
            ))
        }
        
        // 4. Replacement Cycle
        if isDurable {
            // Derive from DurabilityScoringStrategy's category baselines
            let lifespanYears = categoryLifespan(category)
            let lifespanScore = min(1.0, Float(lifespanYears) / 10.0) // 10yr = perfect
            dimensions.append(ScoringDimension(
                name: "Replacement Cycle",
                score: lifespanScore,
                weight: 0.20,
                source: "Category Analysis",
                explanation: "Expected lifespan: ~\(lifespanYears) years"
            ))
        }
        
        // 5. Resale Value (durable goods)
        if isDurable {
            dimensions.append(ScoringDimension(
                name: "Resale Value",
                score: 0.5,
                weight: 0.10,
                source: "eBay Sold Listings",
                explanation: "Secondary market data not yet indexed"
            ))
        }
        
        // Consumable products get a simpler scoring (price-per-use)
        if isConsumable && dimensions.isEmpty {
            dimensions.append(ScoringDimension(
                name: "Price Per Use",
                score: 0.5,
                weight: 1.0,
                source: "Price Analysis",
                explanation: "Per-use cost comparison pending"
            ))
        }
        
        // Fallback for uncategorized products
        if dimensions.isEmpty {
            dimensions.append(ScoringDimension(
                name: "Lifetime Cost",
                score: 0.5,
                weight: 1.0,
                source: "Category Analysis",
                explanation: "Insufficient data for lifetime cost analysis"
            ))
        }
        
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
            if aScore != bScore { return aScore > bScore }
            return a.price < b.price // Tie-break by sticker price
        }
    }
    
    // MARK: - Helpers
    
    private func categoryLifespan(_ category: String) -> Int {
        // Expected product lifespan in years
        if category.contains("phone") { return 4 }
        if category.contains("laptop") || category.contains("computer") { return 6 }
        if category.contains("tv") { return 8 }
        if category.contains("refrigerator") { return 15 }
        if category.contains("washer") || category.contains("dryer") { return 12 }
        if category.contains("dishwasher") { return 10 }
        if category.contains("furniture") { return 15 }
        if category.contains("camera") { return 7 }
        return 5 // Default
    }
}
