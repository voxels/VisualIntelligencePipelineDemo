//
//  ProductRecommendationService.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service that generates ranked product recommendations by:
/// 1. **Retrieve** — Search platform product pages using product classification
/// 2. **Score** — Run each result through the active `ProductScoringStrategy`
/// 3. **Rank** — Sort by composite score (strategy × brand affinity × trend signal)
/// 4. **Generate** — SLM produces advisory signal from top-scored context
///
/// Brand affinity is computed from `UserConcept` weights in the knowledge graph.
public final class ProductRecommendationService: ProductRecommending, @unchecked Sendable {
    
    private let esgService: (any ESGEnriching)?
    
    public init(esgService: (any ESGEnriching)? = nil) {
        self.esgService = esgService
    }
    
    public func recommend(
        for product: ProductClassification,
        using strategy: any ProductScoringStrategy,
        brandAffinities: [BrandProfile],
        priceTrend: PriceTrajectory?,
        strategyWeights: [String: Float] = PreferenceLearner.defaultWeights
    ) async throws -> [RankedRecommendation] {
        // Step 1: Score the detected product itself
        let enrichment: (any Sendable)? = try? await fetchEnrichment(for: product, strategy: strategy)
        let productScore = try await strategy.score(product, enrichment: enrichment)
        
        // Step 2: Compute brand affinity
        let brandAffinity = computeBrandAffinity(for: product.brand, from: brandAffinities)
        
        // Step 3: Compute trend factor
        let trendFactor = computeTrendFactor(priceTrend)
        
        // Step 4: Build composite score using preference-learned weights
        // Strategy weight comes from what the user actually owns —
        // high ownership scores in a dimension → higher weight here
        let strategyWeight = strategyWeights[strategy.strategyID] ?? 0.25
        let compositeScore = (productScore.overallScore * strategyWeight * 2.0) // Scale since weights sum to 1
            + (brandAffinity * 0.3)
            + (trendFactor * 0.2)
        
        // For Phase 0, we return the product itself as the primary recommendation.
        // In Phase 2, this will be expanded with RAG search against platform APIs.
        // Generate a real affiliate URL using the routing service
        let affiliateRouter = AffiliateRoutingService()
        let rankedPlatforms = try? await affiliateRouter.rankPlatforms(
            for: product,
            policy: EthicalPolicy()
        )
        let topPlatform = rankedPlatforms?.first
        let fallbackURL = try? await affiliateRouter.affiliateLink(for: product, platform: "target")
        let affiliateURL: URL? = topPlatform?.affiliateURL ?? fallbackURL
        
        let option = PurchaseOption(
            platform: topPlatform?.platform ?? "detected",
            productName: product.name,
            brand: product.brand,
            price: 0, // Price not available from detection alone
            currency: "USD",
            scores: [productScore],
            affiliateURL: affiliateURL ?? URL(string: "https://www.target.com/s?searchTerm=\(product.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? product.name)")!
        )
        
        let recommendation = RankedRecommendation(
            option: option,
            brandAffinity: brandAffinity,
            compositeScore: compositeScore
        )
        
        return [recommendation]
    }
    
    // MARK: - Advisory Signal Generation
    
    /// Generate an advisory signal from commerce context using the on-device SLM.
    /// Returns nil if FoundationModels is unavailable or the context is empty.
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    public func generateAdvisory(from commerceContext: String) async throws -> AdvisorySignalOutput? {
        let instructions = """
        Analyze the product scoring and economic trend data to recommend whether to buy now, wait, or consider alternatives.
        
        Consider:
        1. Product scoring (sustainability, quality, certifications)
        2. Price trends (rising = buy now, falling = wait)
        3. Brand reputation
        4. Overall value assessment
        
        Be concise. Your explanation should be one sentence.
        """
        
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: commerceContext,
            generating: AdvisorySignalOutput.self,
            options: GenerationOptions(sampling: .greedy)
        )
        
        return response.content
    }
    
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    public func generateInsight(from commerceContext: String) async throws -> ProductInsight? {
        let instructions = """
        Provide a brief product assessment based on the scoring data provided.
        Focus on key differentiators that matter to a consumer making a purchase decision.
        Include brand reputation if brand information is available.
        """
        
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: commerceContext,
            generating: ProductInsight.self,
            options: GenerationOptions(sampling: .greedy)
        )
        
        return response.content
    }
    #endif
    
    // MARK: - Private Helpers
    
    private func fetchEnrichment(for product: ProductClassification, strategy: any ProductScoringStrategy) async throws -> (any Sendable)? {
        // For ESG strategy, fetch ESG enrichment data
        if strategy.strategyID == "esg", let esgService {
            if let barcode = product.barcode {
                return try await esgService.enrich(barcode: barcode)
            } else {
                return try await esgService.enrich(category: product.category)
            }
        }
        return nil
    }
    
    private func computeBrandAffinity(for brand: String?, from affinities: [BrandProfile]) -> Float {
        guard let brand else { return 0.5 } // Neutral when brand unknown
        
        // Find matching brand in user's affinity list
        if let match = affinities.first(where: { $0.name.caseInsensitiveCompare(brand) == .orderedSame }) {
            return match.userAffinity
        }
        
        return 0.3 // Below-neutral for unknown brands (user hasn't interacted)
    }
    
    private func computeTrendFactor(_ trend: PriceTrajectory?) -> Float {
        guard let trend else { return 0.5 } // Neutral when no trend data
        
        switch trend.projectedDirection {
        case .rising:
            // Prices rising → buy now (higher factor = more urgency)
            return 0.7 + (0.3 * trend.confidenceInterval) // 0.7 – 1.0
        case .falling:
            // Prices falling → wait (lower factor = less urgency)
            return 0.3 - (0.2 * trend.confidenceInterval) // 0.1 – 0.3
        case .stable:
            return 0.5
        }
    }
}
