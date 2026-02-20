//
//  PreferenceLearnerTests.swift
//  DiverKitTests
//
//  TDD tests for PreferenceLearner weight derivation logic.
//  Tests the pure static functions — no SwiftData context needed
//  for deriveWeights (fetchScoringHistory tested separately via mock).
//

import Testing
import Foundation
@testable import DiverKit
@testable import DiverShared

@Suite("PreferenceLearner")
struct PreferenceLearnerTests {
    
    // MARK: - Default Weights
    
    @Test("Default weights sum to approximately 1.0")
    func defaultWeightsSum() {
        let total = PreferenceLearner.defaultWeights.values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.01, "Sum was \(total)")
    }
    
    @Test("Default weights include all 7 strategy IDs")
    func defaultWeightsKeys() {
        let expected: Set<String> = ["esg", "brand", "value", "durability", "social", "health", "totalcost"]
        let actual = Set(PreferenceLearner.defaultWeights.keys)
        #expect(actual == expected)
    }
    
    @Test("Default weights are roughly equal")
    func defaultWeightsEqual() {
        for (_, weight) in PreferenceLearner.defaultWeights {
            #expect(abs(weight - 0.143) < 0.01, "Weight should be ~0.143")
        }
    }
    
    // MARK: - deriveWeights: Basic Behavior
    
    @Test("Returns defaults when no scores provided")
    func deriveWeightsEmpty() {
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: [:])
        #expect(weights == PreferenceLearner.defaultWeights)
    }
    
    @Test("Returns defaults when all score arrays are empty")
    func deriveWeightsEmptyArrays() {
        let scores: [String: [Float]] = [
            "esg": [],
            "brand": [],
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        #expect(weights == PreferenceLearner.defaultWeights)
    }
    
    @Test("Amplifies high-scoring strategies over low-scoring ones")
    func deriveWeightsAmplification() {
        let scores: [String: [Float]] = [
            "esg": [0.9, 0.85, 0.95],    // Consistently high
            "value": [0.3, 0.2, 0.25],   // Consistently low
            "brand": [0.5, 0.5, 0.5],    // Neutral
        ]
        
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        #expect(weights["esg"]! > weights["value"]!)
        #expect(weights["esg"]! > weights["brand"]!)
        #expect(weights["brand"]! > weights["value"]!)
    }
    
    @Test("Normalized sum is always 1.0")
    func deriveWeightsNormalized() {
        let scores: [String: [Float]] = [
            "esg": [0.7],
            "brand": [0.9],
            "durability": [0.3],
            "social": [0.8],
        ]
        
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        let total = weights.values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.01, "Sum was \(total)")
    }
    
    // MARK: - deriveWeights: Floor Enforcement
    
    @Test("Enforces floor on strategies with no data")
    func deriveWeightsFloor() {
        let scores: [String: [Float]] = [
            "esg": [1.0, 1.0, 1.0],  // Only esg has data
        ]
        
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        
        // ESG should dominate
        #expect(weights["esg"]! > 0.2)
        
        // All other known strategies should have at least floor weight
        for id in ["brand", "value", "durability", "social", "health", "totalcost"] {
            #expect(weights[id] != nil, "Missing weight for \(id)")
            // After floor (0.05) + renormalization, should be > 0.03
            #expect(weights[id]! >= 0.03, "\(id) below effective floor: \(weights[id]!)")
        }
    }
    
    @Test("All 7 strategies present in output even with partial input")
    func deriveWeightsAllPresent() {
        let scores: [String: [Float]] = [
            "health": [0.8],
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        #expect(weights.count == 7, "Should always have all 7 strategies")
    }
    
    // MARK: - Edge Cases
    
    @Test("All zero scores produce valid weights")
    func deriveWeightsAllZero() {
        let scores: [String: [Float]] = [
            "esg": [0.0, 0.0],
            "brand": [0.0, 0.0],
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        // Squaring zeros gives zero → should fall back to defaults
        let total = weights.values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.01)
    }
    
    @Test("Single product single strategy produces valid weights")
    func deriveWeightsSingle() {
        let scores: [String: [Float]] = [
            "health": [0.8],
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        #expect(weights["health"]! > 0.2, "Single strategy with data should dominate")
        let total = weights.values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.01)
    }
    
    @Test("100 products produce stable weights")
    func deriveWeightsManyProducts() {
        let scores: [String: [Float]] = [
            "esg": Array(repeating: Float(0.8), count: 100),
            "value": Array(repeating: Float(0.2), count: 100),
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        #expect(weights["esg"]! > weights["value"]!)
    }
    
    @Test("Scores capped at 1.0 after sharing boost produce valid weights")
    func deriveWeightsAboveOne() {
        let scores: [String: [Float]] = [
            "esg": [1.0, 1.0],  // Max after clamping in fetchScoringHistory
            "brand": [0.5, 0.5],
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        #expect(weights["esg"]! > weights["brand"]!)
        let total = weights.values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.01)
    }
    
    @Test("Identical scores across all strategies produce roughly equal weights")
    func deriveWeightsIdentical() {
        let scores: [String: [Float]] = [
            "esg": [0.7, 0.7],
            "brand": [0.7, 0.7],
            "value": [0.7, 0.7],
            "durability": [0.7, 0.7],
            "social": [0.7, 0.7],
            "health": [0.7, 0.7],
            "totalcost": [0.7, 0.7],
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        
        // All should be roughly 0.143
        let avg = 1.0 / 7.0
        for (id, weight) in weights {
            #expect(abs(Float(avg) - weight) < 0.02, "\(id) weight \(weight) too far from \(avg)")
        }
    }
    
    @Test("Unknown strategy IDs in input are preserved alongside defaults")
    func deriveWeightsUnknownStrategy() {
        let scores: [String: [Float]] = [
            "esg": [0.9],
            "newengine": [0.8],  // Not in defaultWeights
        ]
        let weights = PreferenceLearner.deriveWeights(from: [], allScores: scores)
        // Should still have all 7 known strategies + the unknown one
        #expect(weights["newengine"] != nil)
        #expect(weights.count >= 7)
    }
}
