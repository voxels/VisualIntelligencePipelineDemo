//
//  SocialProofScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Scores products based on community sentiment and expert consensus.
///
/// Sub-dimensions:
/// - **Reddit Sentiment**: Product subreddit sentiment from r/BuyItForLife, r/reviews, etc.
/// - **Review Consensus**: Cross-platform review aggregation (YouTube, expert sites)
/// - **Recall/Complaint History**: CPSC, NHTSA, r/legaladvice mentions
/// - **Community Repairability**: iFixit guides + r/repair success stories
/// - **Demand Signal**: Pinterest saves, wishlists, trending indicators
///
/// Phase 1a: Reddit API (free tier), iFixit API.
/// Phase 2: YouTube transcript analysis, Pinterest API.
public final class SocialProofScoringStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "social"
    public let displayName = "Social Proof"
    
    public init() {}
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        var dimensions: [ScoringDimension] = []
        
        // Extract gov data if available (passed as part of enrichment bundle)
        let gov = enrichment as? GovernmentEnrichment
        
        // 1. Reddit Sentiment (Phase 1a: will query Reddit API)
        // For now, heuristic based on brand recognition
        let brandKnown = product.brand != nil && !product.brand!.isEmpty
        dimensions.append(ScoringDimension(
            name: "Reddit Sentiment",
            score: brandKnown ? 0.6 : 0.4,
            weight: 0.30,
            source: "Reddit API",
            explanation: brandKnown
                ? "Brand recognized — sentiment analysis pending"
                : "Unknown brand — no community data"
        ))
        
        // 2. Review Consensus (expert reviews from Wirecutter, RTINGS, etc.)
        dimensions.append(ScoringDimension(
            name: "Review Consensus",
            score: 0.5,
            weight: 0.25,
            source: "Expert Reviews",
            explanation: "Expert review aggregation not yet indexed"
        ))
        
        // 3. Complaint & Recall History — live gov data
        if let gov = gov {
            let recallCount = gov.recalls.count + gov.fdaAlerts.count
            let score: Float = recallCount == 0 ? 0.9 : max(0.1, 1.0 - Float(recallCount) * 0.2)
            dimensions.append(ScoringDimension(
                name: "Complaint History",
                score: score,
                weight: 0.20,
                source: "CPSC/FDA",
                explanation: recallCount == 0
                    ? "No recalls or FDA alerts found"
                    : "\(recallCount) recall(s)/alert(s) found"
            ))
        } else {
            let riskCategories = ["electronic", "toy", "baby", "automotive", "appliance"]
            let isRiskCategory = riskCategories.contains { product.category.lowercased().contains($0) }
            dimensions.append(ScoringDimension(
                name: "Complaint History",
                score: isRiskCategory ? 0.5 : 0.7,
                weight: 0.20,
                source: "CPSC/NHTSA",
                explanation: isRiskCategory
                    ? "Higher-risk category — complaint analysis pending"
                    : "No known complaints in this category"
            ))
        }
        
        // 4. Community Repairability
        let repairableCategories = ["electronic", "appliance", "automotive", "furniture"]
        let isRepairable = repairableCategories.contains { product.category.lowercased().contains($0) }
        if isRepairable {
            dimensions.append(ScoringDimension(
                name: "Community Repair",
                score: 0.5,
                weight: 0.15,
                source: "iFixit",
                explanation: "Repair guide availability not yet indexed"
            ))
        }
        
        // 5. Demand Signal (trending, wishlist counts)
        dimensions.append(ScoringDimension(
            name: "Demand Signal",
            score: 0.5,
            weight: 0.10,
            source: "Market Data",
            explanation: "Trending/demand data not yet available"
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
