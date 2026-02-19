//
//  PreferenceLearner.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import SwiftData
import DiverShared

/// Derives per-strategy scoring weights from the user's owned product history.
///
/// Products you own are ground truth for what you value. If you consistently
/// buy high-ESG products, the Ethics weight increases. If durability is a
/// pattern in your purchases, that strategy weighs more in future recommendations.
///
/// The learned weights are used in composite score calculation:
/// `compositeScore = Σ(strategyScore × learnedWeight) + brandAffinity + trendFactor`
public struct PreferenceLearner: Sendable {
    
    /// Default equal weights when no ownership history exists.
    /// All 7 engines start equal; ownership patterns shift the balance.
    public static let defaultWeights: [String: Float] = [
        "esg": 0.143,
        "brand": 0.143,
        "value": 0.143,
        "durability": 0.143,
        "social": 0.143,
        "health": 0.143,
        "totalcost": 0.142
    ]
    
    /// Derives strategy weights from owned product scores.
    ///
    /// Algorithm:
    /// 1. Fetch all `OwnedProduct` records with scoring history
    /// 2. For each strategy, compute the average score across owned products
    /// 3. Higher average = user consistently buys high-scoring products in this dimension
    /// 4. Normalize to weights that sum to 1.0
    ///
    /// This means: if your owned products score 0.9 on Ethics and 0.3 on Value,
    /// you put your money where your values are — Ethics gets ~3× the weight.
    public static func deriveWeights(
        from ownedProducts: [OwnedProduct],
        allScores: [String: [Float]] // strategyID → scores for each owned product
    ) -> [String: Float] {
        guard !allScores.isEmpty else { return defaultWeights }
        
        // Compute average score per strategy across all owned products
        var averages: [String: Float] = [:]
        for (strategyID, scores) in allScores {
            guard !scores.isEmpty else { continue }
            averages[strategyID] = scores.reduce(0, +) / Float(scores.count)
        }
        
        guard !averages.isEmpty else { return defaultWeights }
        
        // Higher averages = user values that dimension more
        // Apply softmax-like scaling to amplify preferences
        let amplified = averages.mapValues { powf($0, 2.0) } // Square to amplify differences
        let total = amplified.values.reduce(0, +)
        
        guard total > 0 else { return defaultWeights }
        
        // Normalize to sum = 1.0
        var weights = amplified.mapValues { $0 / total }
        
        // Ensure all known strategies have at least a floor weight (5%)
        // so no strategy is completely ignored
        let floor: Float = 0.05
        let knownStrategies = Set(defaultWeights.keys)
        for id in knownStrategies {
            if weights[id] == nil || weights[id]! < floor {
                weights[id] = floor
            }
        }
        
        // Renormalize after floor application
        let finalTotal = weights.values.reduce(0, +)
        if finalTotal > 0 {
            weights = weights.mapValues { $0 / finalTotal }
        }
        
        return weights
    }
    
    /// Fetches scoring history from owned products using their linked ProcessedItem data.
    /// Returns strategyID → [score] mapping across all owned products.
    /// Shared products get a 1.5× weight boost (sharing = strongest endorsement).
    public static func fetchScoringHistory(
        ownedProducts: [OwnedProduct],
        modelContext: ModelContext
    ) -> [String: [Float]] {
        var history: [String: [Float]] = [:]
        
        for owned in ownedProducts {
            guard let captureID = owned.captureItemID else { continue }
            
            // Source-based weight multiplier:
            // Sharing with a contact is the strongest quality signal
            let sourceMultiplier: Float = switch owned.source {
            case .shared: 1.5   // Strongest endorsement — you'd recommend it
            case .tagScan: 1.0  // You own it
            case .financeKit: 1.0
            case .manual: 0.9
            case .ctaTap: 0.7   // Considering, not confirmed
            }
            
            let fetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.id == captureID }
            )
            guard let item = try? modelContext.fetch(fetch).first,
                  let context = item.commerceContext else { continue }
            
            for rec in context {
                for score in rec.option.scores {
                    // Apply source multiplier to amplify/dampen this product's contribution
                    let weightedScore = min(1.0, score.overallScore * sourceMultiplier)
                    history[score.strategyID, default: []].append(weightedScore)
                }
            }
        }
        
        return history
    }
}
