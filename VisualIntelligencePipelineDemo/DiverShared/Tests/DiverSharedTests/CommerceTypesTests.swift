//
//  CommerceTypesTests.swift
//  DiverSharedTests
//
//  Created by Antigravity on 02/19/26.
//

import Testing
import Foundation
@testable import DiverShared

struct CommerceTypesTests {
    
    // MARK: - ProductClassification
    
    @Test("ProductClassification encodes and decodes correctly")
    func productClassificationRoundtrip() throws {
        let original = ProductClassification(
            productID: "123456789012",
            name: "Organic Oat Milk",
            category: "food",
            brand: "Oatly",
            barcode: "123456789012",
            confidence: 0.92
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProductClassification.self, from: data)
        
        #expect(decoded.productID == original.productID)
        #expect(decoded.name == original.name)
        #expect(decoded.brand == "Oatly")
        #expect(decoded.barcode == "123456789012")
        #expect(decoded.confidence == 0.92)
    }
    
    // MARK: - ProductScore
    
    @Test("ProductScore with dimensions encodes/decodes")
    func productScoreRoundtrip() throws {
        let score = ProductScore(
            strategyID: "esg",
            overallScore: 0.73,
            dimensions: [
                ScoringDimension(name: "Carbon", score: 0.65, weight: 0.4, source: "Climate TRACE", explanation: "2.3 kg CO₂e"),
                ScoringDimension(name: "Certs", score: 0.80, weight: 0.3, source: "Open Food Facts", explanation: "Fair Trade")
            ]
        )
        
        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(ProductScore.self, from: data)
        
        #expect(decoded.strategyID == "esg")
        #expect(decoded.overallScore == 0.73)
        #expect(decoded.dimensions.count == 2)
        #expect(decoded.dimensions[0].name == "Carbon")
        #expect(decoded.dimensions[1].weight == 0.3)
    }
    
    // MARK: - PriceTrajectory
    
    @Test("PriceTrajectory with data points roundtrips")
    func priceTrajectoryRoundtrip() throws {
        let trajectory = PriceTrajectory(
            commodityID: "wheat",
            dataPoints: [
                PriceDataPoint(date: Date(), value: 5.99, isProjected: false),
                PriceDataPoint(date: Date().addingTimeInterval(86400 * 7), value: 6.15, isProjected: true)
            ],
            projectedDirection: .rising,
            confidenceInterval: 0.78,
            horizonDays: 14
        )
        
        let data = try JSONEncoder().encode(trajectory)
        let decoded = try JSONDecoder().decode(PriceTrajectory.self, from: data)
        
        #expect(decoded.commodityID == "wheat")
        #expect(decoded.dataPoints.count == 2)
        #expect(decoded.projectedDirection == .rising)
        #expect(decoded.horizonDays == 14)
        #expect(decoded.dataPoints[1].isProjected == true)
    }
    
    // MARK: - TrendDirection
    
    @Test("TrendDirection raw values are stable")
    func trendDirectionValues() {
        #expect(TrendDirection.rising.rawValue == "rising")
        #expect(TrendDirection.falling.rawValue == "falling")
        #expect(TrendDirection.stable.rawValue == "stable")
    }
    
    // MARK: - PurchaseOption
    
    @Test("PurchaseOption encodes with scores")
    func purchaseOptionRoundtrip() throws {
        let option = PurchaseOption(
            platform: "amazon",
            productName: "Test Widget",
            brand: "Acme",
            price: 29.99,
            currency: "USD",
            scores: [
                ProductScore(strategyID: "esg", overallScore: 0.8, dimensions: [])
            ],
            affiliateURL: URL(string: "https://amazon.com/dp/test")!
        )
        
        let data = try JSONEncoder().encode(option)
        let decoded = try JSONDecoder().decode(PurchaseOption.self, from: data)
        
        #expect(decoded.platform == "amazon")
        #expect(decoded.price == 29.99)
        #expect(decoded.scores.count == 1)
        #expect(decoded.scores[0].strategyID == "esg")
    }
    
    // MARK: - RankedRecommendation
    
    @Test("RankedRecommendation preserves composite score")
    func rankedRecommendationRoundtrip() throws {
        let option = PurchaseOption(
            platform: "ebay",
            productName: "Used Widget",
            price: 15.00,
            affiliateURL: URL(string: "https://ebay.com/item/123")!
        )
        let rec = RankedRecommendation(
            option: option,
            brandAffinity: 0.65,
            compositeScore: 0.72
        )
        
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(RankedRecommendation.self, from: data)
        
        #expect(decoded.brandAffinity == 0.65)
        #expect(decoded.compositeScore == 0.72)
        #expect(decoded.option.platform == "ebay")
    }
    
    // MARK: - ESGEnrichment
    
    @Test("ESGEnrichment handles optional fields")
    func esgEnrichmentOptionals() throws {
        let minimal = ESGEnrichment(
            dataQualityTier: 5,
            source: "Climate TRACE"
        )
        
        let data = try JSONEncoder().encode(minimal)
        let decoded = try JSONDecoder().decode(ESGEnrichment.self, from: data)
        
        #expect(decoded.carbonIntensity == nil)
        #expect(decoded.ecoScore == nil)
        #expect(decoded.certifications.isEmpty)
        #expect(decoded.dataQualityTier == 5)
    }
    
    // MARK: - BrandProfile
    
    @Test("BrandProfile hashable and codable")
    func brandProfileRoundtrip() throws {
        let brand = BrandProfile(
            name: "Oatly",
            category: "food",
            userAffinity: 0.85,
            productCount: 12
        )
        
        let data = try JSONEncoder().encode(brand)
        let decoded = try JSONDecoder().decode(BrandProfile.self, from: data)
        
        #expect(decoded.name == "Oatly")
        #expect(decoded.userAffinity == 0.85)
        #expect(decoded == brand) // Hashable
    }
    
    // MARK: - PurchaseOutcome & Ownership
    
    @Test("PurchaseOutcome records ownership with scoring context")
    func purchaseOutcomeRoundtrip() throws {
        let outcome = PurchaseOutcome(
            productID: "barcode-123",
            brand: "Patagonia",
            category: "clothing",
            status: .owned,
            source: .tagScan,
            scoringContext: ["esg", "brand", "durability"],
            recommendedCompositeScore: 0.81
        )
        
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(PurchaseOutcome.self, from: data)
        
        #expect(decoded.status == .owned)
        #expect(decoded.source == .tagScan)
        #expect(decoded.scoringContext.count == 3)
        #expect(decoded.recommendedCompositeScore == 0.81)
        #expect(decoded.brand == "Patagonia")
    }
    
    @Test("OwnershipStatus transitions are valid raw values")
    func ownershipStatusValues() {
        #expect(OwnershipStatus.owned.rawValue == "owned")
        #expect(OwnershipStatus.considering.rawValue == "considering")
        #expect(OwnershipStatus.returned.rawValue == "returned")
        #expect(OwnershipStatus.wishlisted.rawValue == "wishlisted")
    }
    
    @Test("OutcomeSource captures all acquisition paths")
    func outcomeSourceValues() {
        #expect(OutcomeSource.tagScan.rawValue == "tagScan")
        #expect(OutcomeSource.ctaTap.rawValue == "ctaTap")
        #expect(OutcomeSource.financeKit.rawValue == "financeKit")
        #expect(OutcomeSource.manual.rawValue == "manual")
    }
}
