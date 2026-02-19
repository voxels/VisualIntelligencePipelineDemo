//
//  CommerceV2Tests.swift
//  DiverSharedTests
//
//  TDD checkpoint tests for Spec v2 commerce additions:
//  - ESGEnrichment text context expansion + edge cases
//  - StrategyScoreEntry roundtrips
//  - OutcomeSource.shared
//  - PreferenceLearner weight derivation (pure logic)
//

import Testing
import Foundation
@testable import DiverShared

// MARK: - ESGEnrichment Text Context

@Suite("ESGEnrichment Text Context")
struct ESGEnrichmentTextTests {
    
    @Test("Stores and exposes all 12 text fields")
    func allTextFields() {
        let enrichment = ESGEnrichment(
            carbonIntensity: 2.5,
            dataQualityTier: 2,
            certifications: ["Fair Trade", "Organic"],
            ecoScore: "b",
            source: "Open Food Facts",
            ingredientsText: "water, sugar, cocoa",
            allergens: ["Milk", "Soy"],
            traces: ["Nuts"],
            origins: "Switzerland",
            manufacturingPlaces: "Zurich",
            novaGroup: 3,
            nutriScore: "c",
            nutriments: ["energy_kcal": 250, "sugars": 12, "proteins": 8],
            packagingText: "Recyclable cardboard",
            quantity: "200g",
            genericName: "Chocolate bar",
            countriesSold: ["Switzerland", "Germany", "France"],
            stores: ["Migros", "Coop"]
        )
        
        #expect(enrichment.ingredientsText == "water, sugar, cocoa")
        #expect(enrichment.allergens == ["Milk", "Soy"])
        #expect(enrichment.traces == ["Nuts"])
        #expect(enrichment.origins == "Switzerland")
        #expect(enrichment.manufacturingPlaces == "Zurich")
        #expect(enrichment.novaGroup == 3)
        #expect(enrichment.nutriScore == "c")
        #expect(enrichment.nutriments["sugars"] == 12)
        #expect(enrichment.nutriments.count == 3)
        #expect(enrichment.packagingText == "Recyclable cardboard")
        #expect(enrichment.quantity == "200g")
        #expect(enrichment.genericName == "Chocolate bar")
        #expect(enrichment.countriesSold.count == 3)
        #expect(enrichment.stores.contains("Migros"))
    }
    
    @Test("Default init has empty arrays and nil text fields")
    func defaultInit() {
        let minimal = ESGEnrichment(dataQualityTier: 5, source: "test")
        #expect(minimal.ingredientsText == nil)
        #expect(minimal.allergens.isEmpty)
        #expect(minimal.traces.isEmpty)
        #expect(minimal.origins == nil)
        #expect(minimal.manufacturingPlaces == nil)
        #expect(minimal.novaGroup == nil)
        #expect(minimal.nutriScore == nil)
        #expect(minimal.nutriments.isEmpty)
        #expect(minimal.packagingText == nil)
        #expect(minimal.quantity == nil)
        #expect(minimal.genericName == nil)
        #expect(minimal.countriesSold.isEmpty)
        #expect(minimal.stores.isEmpty)
    }
    
    @Test("contextSummary includes only populated fields")
    func contextSummaryMinimal() {
        let minimal = ESGEnrichment(dataQualityTier: 5, source: "Climate TRACE")
        let summary = minimal.contextSummary
        #expect(summary.contains("Source: Climate TRACE, Tier 5"))
        #expect(!summary.contains("Ingredients:"))
        #expect(!summary.contains("Allergens:"))
        #expect(!summary.contains("Product:"))
    }
    
    @Test("contextSummary includes all populated fields")
    func contextSummaryFull() {
        let full = ESGEnrichment(
            carbonIntensity: 1.5,
            dataQualityTier: 2,
            certifications: ["Organic"],
            ecoScore: "a",
            source: "Open Food Facts",
            ingredientsText: "oats, water",
            allergens: ["Gluten"],
            novaGroup: 1,
            nutriScore: "a",
            nutriments: ["sugars": 3.0],
            genericName: "Oat milk"
        )
        let summary = full.contextSummary
        #expect(summary.contains("Product: Oat milk"))
        #expect(summary.contains("Ingredients: oats, water"))
        #expect(summary.contains("Allergens: Gluten"))
        #expect(summary.contains("NOVA processing level: 1/4"))
        #expect(summary.contains("Nutri-Score: A"))
        #expect(summary.contains("Eco-Score: A"))
        #expect(summary.contains("Carbon: 1.5 kg"))
        #expect(summary.contains("Certifications: Organic"))
    }
    
    // Edge cases
    
    @Test("contextSummary handles empty string ingredients")
    func contextSummaryEmptyIngredients() {
        let enrichment = ESGEnrichment(
            dataQualityTier: 4,
            source: "test",
            ingredientsText: ""
        )
        // Empty string is still non-nil, should appear
        #expect(enrichment.contextSummary.contains("Ingredients: "))
    }
    
    @Test("NOVA group boundary values")
    func novaGroupBoundaries() {
        for group in [1, 2, 3, 4] {
            let e = ESGEnrichment(dataQualityTier: 3, source: "test", novaGroup: group)
            #expect(e.contextSummary.contains("NOVA processing level: \(group)/4"))
        }
    }
    
    @Test("nutriments with zero values")
    func nutrimentsZero() {
        let e = ESGEnrichment(
            dataQualityTier: 3,
            source: "test",
            nutriments: ["sugars": 0.0, "fat": 0.0]
        )
        #expect(e.nutriments["sugars"] == 0.0)
        #expect(e.contextSummary.contains("Nutrition:"))
    }
    
    @Test("Codable roundtrip preserves all text fields")
    func codableRoundtrip() throws {
        let original = ESGEnrichment(
            carbonIntensity: 3.0,
            dataQualityTier: 3,
            certifications: ["B Corp"],
            ecoScore: "c",
            source: "Open Beauty Facts",
            ingredientsText: "aqua, glycerin",
            allergens: [],
            traces: ["Fragrance"],
            origins: "France",
            novaGroup: nil,
            nutriScore: nil,
            nutriments: ["fat": 5.0],
            quantity: "250ml",
            genericName: nil,
            countriesSold: ["France", "Belgium"],
            stores: []
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ESGEnrichment.self, from: data)
        
        #expect(decoded.ingredientsText == "aqua, glycerin")
        #expect(decoded.allergens.isEmpty)
        #expect(decoded.traces == ["Fragrance"])
        #expect(decoded.origins == "France")
        #expect(decoded.quantity == "250ml")
        #expect(decoded.genericName == nil)
        #expect(decoded.nutriments["fat"] == 5.0)
        #expect(decoded.countriesSold.count == 2)
        #expect(decoded.stores.isEmpty)
        #expect(decoded.source == "Open Beauty Facts")
    }
    
    @Test("Codable roundtrip with all nil text fields")
    func codableRoundtripAllNil() throws {
        let original = ESGEnrichment(dataQualityTier: 5, source: "sector")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ESGEnrichment.self, from: data)
        #expect(decoded.ingredientsText == nil)
        #expect(decoded.novaGroup == nil)
        #expect(decoded.nutriments.isEmpty)
    }
}

// MARK: - OutcomeSource

@Suite("OutcomeSource")
struct OutcomeSourceTests {
    
    @Test("All cases have stable raw values")
    func rawValueStability() {
        #expect(OutcomeSource.tagScan.rawValue == "tagScan")
        #expect(OutcomeSource.ctaTap.rawValue == "ctaTap")
        #expect(OutcomeSource.financeKit.rawValue == "financeKit")
        #expect(OutcomeSource.manual.rawValue == "manual")
        #expect(OutcomeSource.shared.rawValue == "shared")
    }
    
    @Test("All cases roundtrip through Codable")
    func roundtrip() throws {
        let cases: [OutcomeSource] = [.tagScan, .ctaTap, .financeKit, .manual, .shared]
        for source in cases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(OutcomeSource.self, from: data)
            #expect(decoded == source)
        }
    }
    
    @Test("Invalid raw value returns nil")
    func invalidRawValue() {
        #expect(OutcomeSource(rawValue: "unknown") == nil)
        #expect(OutcomeSource(rawValue: "") == nil)
    }
}

// MARK: - StrategyScoreEntry

@Suite("StrategyScoreEntry")
struct StrategyScoreEntryTests {
    
    @Test("id equals strategyID")
    func idEquality() {
        let entry = StrategyScoreEntry(strategyID: "esg", displayName: "Ethics", score: 0.85)
        #expect(entry.id == "esg")
        #expect(entry.id == entry.strategyID)
    }
    
    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let entry = StrategyScoreEntry(strategyID: "totalcost", displayName: "Total Cost", score: 0.42)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(StrategyScoreEntry.self, from: data)
        #expect(decoded.strategyID == "totalcost")
        #expect(decoded.displayName == "Total Cost")
        #expect(decoded.score == 0.42)
    }
    
    @Test("Array roundtrip preserves order")
    func arrayRoundtrip() throws {
        let entries = [
            StrategyScoreEntry(strategyID: "esg", displayName: "Ethics", score: 0.9),
            StrategyScoreEntry(strategyID: "social", displayName: "Social", score: 0.6),
            StrategyScoreEntry(strategyID: "health", displayName: "Health", score: 0.75),
            StrategyScoreEntry(strategyID: "totalcost", displayName: "Total Cost", score: 0.5),
        ]
        
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([StrategyScoreEntry].self, from: data)
        #expect(decoded.count == 4)
        #expect(decoded[0].strategyID == "esg")
        #expect(decoded[3].strategyID == "totalcost")
    }
    
    // Edge cases
    
    @Test("Score boundary values")
    func scoreBoundaries() {
        let zero = StrategyScoreEntry(strategyID: "a", displayName: "A", score: 0.0)
        let one = StrategyScoreEntry(strategyID: "b", displayName: "B", score: 1.0)
        let negative = StrategyScoreEntry(strategyID: "c", displayName: "C", score: -0.1) // shouldn't happen but shouldn't crash
        
        #expect(zero.score == 0.0)
        #expect(one.score == 1.0)
        #expect(negative.score == -0.1)
    }
    
    @Test("Empty array roundtrip")
    func emptyArrayRoundtrip() throws {
        let entries: [StrategyScoreEntry] = []
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([StrategyScoreEntry].self, from: data)
        #expect(decoded.isEmpty)
    }
    
    @Test("Empty string strategyID")
    func emptyStrategyID() {
        let entry = StrategyScoreEntry(strategyID: "", displayName: "", score: 0.5)
        #expect(entry.id == "")
    }
}
