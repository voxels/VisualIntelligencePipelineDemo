//
//  CommerceGenerable.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// SLM-generated buy/wait/alternatives recommendation based on economic trends.
/// This is the **timing** signal — independent of strategy scores.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Purchase timing advisory based on economic trends")
public struct AdvisorySignalOutput {
    @Guide(description: "The timing recommendation: buy, wait, or alternatives")
    public var signal: SignalType
    
    @Guide(description: "One-sentence explanation of the timing recommendation")
    public var explanation: String
    
    @Generable(description: "Type of timing signal")
    public enum SignalType: String {
        case buy
        case wait
        case alternatives
    }
}

/// SLM-generated per-strategy score summary and overall product insight.
/// Synthesizes scores from ALL active scoring engines into human-readable assessments.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Multi-strategy product scoring summary")
public struct ProductInsight {
    @Guide(description: "Per-strategy score summaries, one entry per active scoring engine")
    public var scoreSummaries: [StrategyScoreSummary]
    
    @Guide(description: "Overall product assessment synthesizing all strategy scores")
    public var overallAssessment: String
    
    @Guide(description: "Key differentiators or concerns, 2-3 items")
    public var keyDifferentiators: [String]
    
    @Guide(description: "Brand reputation insight if brand data is available")
    public var brandInsight: String?
}

/// Summary of a single scoring engine's result.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Score summary from one scoring strategy engine")
public struct StrategyScoreSummary {
    @Guide(description: "Strategy identifier: esg, brand, value, durability, etc.")
    public var strategyName: String
    
    @Guide(description: "Human-readable assessment of this strategy's score")
    public var assessment: String
    
    @Guide(description: "Score as percentage string, e.g. '72%'")
    public var scorePercent: String
}

#endif
