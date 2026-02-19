//
//  ScoreSnapshot.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import SwiftData
import DiverShared

/// A point-in-time record of a product's scores across all active strategies.
/// Persisted via SwiftData + CloudKit for historical charting.
///
/// Use cases:
/// - **Product score evolution**: Track how a product's scores change over time
///   (e.g., a brand's Ethics score drops after a recall)
/// - **Price history**: Map price changes over time for shrinkflation/inflation analysis
/// - **Preference profile drift**: Aggregate snapshots show how user values shift
///
/// Consumed by Swift Charts for time-series visualization.
@Model
public final class ScoreSnapshot: @unchecked Sendable {
    public var id: String = UUID().uuidString
    
    /// What this snapshot tracks
    public var productID: String = ""      // ProductClassification.productID or barcode
    public var productName: String = ""
    public var brand: String?
    public var category: String?
    
    /// When this snapshot was recorded
    public var recordedAt: Date = Date()
    
    /// Per-strategy scores at this point in time
    /// Stored as JSON-encoded [StrategyScoreEntry] for flexibility
    public var scoresData: Data?
    
    /// Price at this point in time (if available)
    public var price: Double?
    public var currency: String?
    
    /// Package quantity at this point (for shrinkflation tracking)
    public var quantity: String?
    
    /// Composite score at this point
    public var compositeScore: Double?
    
    /// The learned preference weights at this point in time
    /// JSON-encoded [String: Float] — shows how user's preferences evolved
    public var preferenceWeightsData: Data?
    
    /// Which enrichment source provided this data
    public var source: String?
    
    // MARK: - Computed Accessors
    
    @Transient
    public var strategyScores: [StrategyScoreEntry] {
        get {
            guard let data = scoresData else { return [] }
            return (try? JSONDecoder().decode([StrategyScoreEntry].self, from: data)) ?? []
        }
        set {
            scoresData = try? JSONEncoder().encode(newValue)
        }
    }
    
    @Transient
    public var preferenceWeights: [String: Float] {
        get {
            guard let data = preferenceWeightsData else { return [:] }
            return (try? JSONDecoder().decode([String: Float].self, from: data)) ?? [:]
        }
        set {
            preferenceWeightsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    public init(
        productID: String,
        productName: String,
        brand: String? = nil,
        category: String? = nil,
        strategyScores: [StrategyScoreEntry] = [],
        price: Double? = nil,
        currency: String? = nil,
        quantity: String? = nil,
        compositeScore: Double? = nil,
        preferenceWeights: [String: Float] = [:],
        source: String? = nil
    ) {
        self.id = UUID().uuidString
        self.productID = productID
        self.productName = productName
        self.brand = brand
        self.category = category
        self.recordedAt = Date()
        self.scoresData = try? JSONEncoder().encode(strategyScores)
        self.price = price
        self.currency = currency
        self.quantity = quantity
        self.compositeScore = compositeScore
        self.preferenceWeightsData = try? JSONEncoder().encode(preferenceWeights)
        self.source = source
    }
}
