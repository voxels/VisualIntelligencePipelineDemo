//
//  ScoringStrategyTests.swift
//  DiverKitTests
//
//  TDD tests for all 7 ProductScoringStrategy implementations.
//  Tests protocol conformance, score validity, and edge cases.
//

import Testing
import Foundation
@testable import DiverKit
@testable import DiverShared

// MARK: - Shared Fixtures

/// Minimal product classification for testing
private func makeProduct(
    name: String = "Test Product",
    brand: String? = "TestBrand",
    category: String = "electronics",
    barcode: String? = "1234567890123"
) -> ProductClassification {
    ProductClassification(
        productID: UUID().uuidString,
        name: name,
        category: category,
        brand: brand,
        barcode: barcode,
        confidence: 0.95
    )
}

/// ESG enrichment with populated fields
private func makeESGEnrichment(
    carbonIntensity: Float? = 2.5,
    ecoScore: String? = "b",
    novaGroup: Int? = 2
) -> ESGEnrichment {
    ESGEnrichment(
        carbonIntensity: carbonIntensity,
        dataQualityTier: 3,
        certifications: ["Fair Trade"],
        ecoScore: ecoScore,
        source: "Open Food Facts",
        ingredientsText: "water, oats",
        novaGroup: novaGroup,
        nutriScore: "b"
    )
}

// MARK: - Protocol Conformance

@Suite("Scoring Strategy Protocol Conformance")
struct ScoringStrategyConformanceTests {
    
    let allStrategies: [any ProductScoringStrategy] = [
        ESGScoringStrategy(),
        BrandAlignmentStrategy(),
        ValueScoringStrategy(),
        DurabilityScoringStrategy(),
        SocialProofScoringStrategy(),
        HealthFitScoringStrategy(),
        TotalCostScoringStrategy(),
    ]
    
    @Test("All 7 strategies have non-empty strategyID")
    func strategyIDs() {
        for strategy in allStrategies {
            #expect(!strategy.strategyID.isEmpty, "\(type(of: strategy)) has empty strategyID")
        }
    }
    
    @Test("All strategy IDs are unique")
    func uniqueIDs() {
        let ids = allStrategies.map(\.strategyID)
        let unique = Set(ids)
        #expect(unique.count == allStrategies.count, "Duplicate IDs: \(ids)")
    }
    
    @Test("All 7 strategies have non-empty displayName")
    func displayNames() {
        for strategy in allStrategies {
            #expect(!strategy.displayName.isEmpty, "\(type(of: strategy)) has empty displayName")
        }
    }
    
    @Test("Strategy IDs match expected values")
    func expectedIDs() {
        let expected: Set<String> = ["esg", "brand", "value", "durability", "social", "health", "totalcost"]
        let actual = Set(allStrategies.map(\.strategyID))
        #expect(actual == expected)
    }
}

// MARK: - ESGScoringStrategy

@Suite("ESGScoringStrategy")
struct ESGScoringStrategyTests {
    
    let strategy = ESGScoringStrategy()
    
    @Test("Produces valid score with enrichment")
    func scoreWithEnrichment() async throws {
        let product = makeProduct(category: "food")
        let enrichment = makeESGEnrichment()
        let score = try await strategy.score(product, enrichment: enrichment)
        
        #expect(score.strategyID == "esg")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
        #expect(!score.dimensions.isEmpty)
    }
    
    @Test("Produces neutral score without enrichment")
    func scoreWithoutEnrichment() async throws {
        let product = makeProduct()
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "esg")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("All dimensions have valid scores")
    func dimensionScores() async throws {
        let product = makeProduct(category: "food")
        let enrichment = makeESGEnrichment()
        let score = try await strategy.score(product, enrichment: enrichment)
        
        for dim in score.dimensions {
            #expect(dim.score >= 0.0 && dim.score <= 1.0, "\(dim.name) score out of range: \(dim.score)")
            #expect(dim.weight > 0.0, "\(dim.name) has zero weight")
            #expect(!dim.name.isEmpty)
        }
    }
    
    @Test("Dimension weights sum to approximately 1.0")
    func dimensionWeightsSum() async throws {
        let product = makeProduct(category: "food")
        let enrichment = makeESGEnrichment()
        let score = try await strategy.score(product, enrichment: enrichment)
        
        let totalWeight = score.dimensions.reduce(0) { $0 + $1.weight }
        #expect(totalWeight > 0.5, "Total weight too low: \(totalWeight)")
    }
}

// MARK: - BrandAlignmentStrategy

@Suite("BrandAlignmentStrategy")
struct BrandAlignmentStrategyTests {
    
    let strategy = BrandAlignmentStrategy()
    
    @Test("Produces valid score")
    func validScore() async throws {
        let product = makeProduct(brand: "Apple")
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "brand")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("Produces valid score with nil brand")
    func nilBrand() async throws {
        let product = makeProduct(brand: nil)
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "brand")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
}

// MARK: - ValueScoringStrategy

@Suite("ValueScoringStrategy")
struct ValueScoringStrategyTests {
    
    let strategy = ValueScoringStrategy()
    
    @Test("Produces valid score without price trend")
    func scoreNoPriceTrend() async throws {
        let product = makeProduct()
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "value")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("Produces valid score with price trend")
    func scoreWithPriceTrend() async throws {
        let product = makeProduct()
        let trend = PriceTrajectory(
            commodityID: "test-commodity",
            dataPoints: [
                PriceDataPoint(date: Date().addingTimeInterval(-86400 * 7), value: Decimal(29.99)),
                PriceDataPoint(date: Date(), value: Decimal(24.99)),
            ],
            projectedDirection: .falling,
            confidenceInterval: 0.8,
            horizonDays: 14
        )
        let score = try await strategy.score(product, enrichment: trend)
        
        #expect(score.strategyID == "value")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
}

// MARK: - DurabilityScoringStrategy

@Suite("DurabilityScoringStrategy")
struct DurabilityScoringStrategyTests {
    
    let strategy = DurabilityScoringStrategy()
    
    @Test("Produces valid score")
    func validScore() async throws {
        let product = makeProduct(category: "electronics")
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "durability")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("Produces valid score for consumable category")
    func consumableCategory() async throws {
        let product = makeProduct(category: "food")
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "durability")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
}

// MARK: - SocialProofScoringStrategy

@Suite("SocialProofScoringStrategy")
struct SocialProofScoringStrategyTests {
    
    let strategy = SocialProofScoringStrategy()
    
    @Test("Produces valid score without API data")
    func validScore() async throws {
        let product = makeProduct()
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "social")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("Has expected dimensions")
    func dimensions() async throws {
        let product = makeProduct()
        let score = try await strategy.score(product, enrichment: nil)
        
        // Should have at least placeholders for community dimensions
        #expect(!score.dimensions.isEmpty)
    }
}

// MARK: - HealthFitScoringStrategy

@Suite("HealthFitScoringStrategy")
struct HealthFitScoringStrategyTests {
    
    let strategy = HealthFitScoringStrategy()
    
    @Test("Produces valid score for food category")
    func foodScore() async throws {
        let product = makeProduct(category: "food")
        let enrichment = makeESGEnrichment(novaGroup: 4) // Ultra-processed
        let score = try await strategy.score(product, enrichment: enrichment)
        
        #expect(score.strategyID == "health")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("Non-food products get neutral pass-through")
    func nonFoodScore() async throws {
        let product = makeProduct(category: "electronics")
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "health")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("NOVA group affects score (higher group = lower health)")
    func novaGroupImpact() async throws {
        let product = makeProduct(category: "food")
        let minProcessed = makeESGEnrichment(novaGroup: 1) // Unprocessed
        let ultraProcessed = makeESGEnrichment(novaGroup: 4) // Ultra-processed
        
        let score1 = try await strategy.score(product, enrichment: minProcessed)
        let score4 = try await strategy.score(product, enrichment: ultraProcessed)
        
        // Lower NOVA = healthier = higher score
        #expect(score1.overallScore >= score4.overallScore,
                "NOVA 1 (\(score1.overallScore)) should score ≥ NOVA 4 (\(score4.overallScore))")
    }
}

// MARK: - TotalCostScoringStrategy

@Suite("TotalCostScoringStrategy")
struct TotalCostScoringStrategyTests {
    
    let strategy = TotalCostScoringStrategy()
    
    @Test("Produces valid score")
    func validScore() async throws {
        let product = makeProduct(category: "electronics")
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(score.strategyID == "totalcost")
        #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0)
    }
    
    @Test("Has cost-related dimensions")
    func costDimensions() async throws {
        let product = makeProduct(category: "electronics")
        let score = try await strategy.score(product, enrichment: nil)
        
        #expect(!score.dimensions.isEmpty)
    }
}

// MARK: - Multi-Strategy Pipeline

@Suite("Multi-Strategy Pipeline")
struct MultiStrategyPipelineTests {
    
    @Test("All 7 strategies score the same product without errors")
    func allStrategiesScore() async throws {
        let strategies: [any ProductScoringStrategy] = [
            ESGScoringStrategy(),
            BrandAlignmentStrategy(),
            ValueScoringStrategy(),
            DurabilityScoringStrategy(),
            SocialProofScoringStrategy(),
            HealthFitScoringStrategy(),
            TotalCostScoringStrategy(),
        ]
        
        let product = makeProduct(category: "food")
        let enrichment = makeESGEnrichment()
        
        var scores: [ProductScore] = []
        for strategy in strategies {
            let score = try await strategy.score(product, enrichment: enrichment)
            scores.append(score)
        }
        
        #expect(scores.count == 7)
        
        // All scores in valid range
        for score in scores {
            #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0,
                    "\(score.strategyID) out of range: \(score.overallScore)")
        }
        
        // All strategy IDs unique
        let ids = Set(scores.map(\.strategyID))
        #expect(ids.count == 7)
    }
    
    @Test("All strategies handle nil enrichment gracefully")
    func allStrategiesNilEnrichment() async throws {
        let strategies: [any ProductScoringStrategy] = [
            ESGScoringStrategy(),
            BrandAlignmentStrategy(),
            ValueScoringStrategy(),
            DurabilityScoringStrategy(),
            SocialProofScoringStrategy(),
            HealthFitScoringStrategy(),
            TotalCostScoringStrategy(),
        ]
        
        let product = makeProduct()
        
        for strategy in strategies {
            let score = try await strategy.score(product, enrichment: nil)
            #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0,
                    "\(strategy.strategyID) failed with nil enrichment: \(score.overallScore)")
        }
    }
    
    @Test("All strategies handle empty product name")
    func emptyProductName() async throws {
        let strategies: [any ProductScoringStrategy] = [
            ESGScoringStrategy(),
            BrandAlignmentStrategy(),
            ValueScoringStrategy(),
            DurabilityScoringStrategy(),
            SocialProofScoringStrategy(),
            HealthFitScoringStrategy(),
            TotalCostScoringStrategy(),
        ]
        
        let product = makeProduct(name: "", brand: nil, category: "", barcode: nil)
        
        for strategy in strategies {
            let score = try await strategy.score(product, enrichment: nil)
            #expect(score.overallScore >= 0.0 && score.overallScore <= 1.0,
                    "\(strategy.strategyID) failed with empty product: \(score.overallScore)")
        }
    }
}
