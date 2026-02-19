//
//  OwnedProduct.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import SwiftData
import DiverShared

/// A product the user owns, discovered via barcode/tag scan or purchase confirmation.
/// Persisted via SwiftData + CloudKit for cross-device sync.
///
/// Builds the user's personal brand collection and closes the RAG feedback loop
/// by recording which recommendations led to actual ownership.
@Model
public final class OwnedProduct: @unchecked Sendable {
    public var id: String = UUID().uuidString
    public var productID: String = ""           // ProductClassification.productID or barcode
    public var productName: String = ""
    public var brand: String?
    public var category: String?
    public var barcode: String?
    
    // Ownership
    public var statusRaw: String = OwnershipStatus.owned.rawValue
    public var sourceRaw: String = OutcomeSource.tagScan.rawValue
    public var acquiredAt: Date = Date()
    
    // RAG validation: what scores were active when this was recommended
    public var scoringStrategyIDs: [String] = []   // ["esg", "brand", "value", "durability"]
    public var recommendedScore: Double?            // Composite score at recommendation time
    
    // Link to the ProcessedItem that captured this product
    public var captureItemID: String?
    
    @Transient
    public var status: OwnershipStatus {
        get { OwnershipStatus(rawValue: statusRaw) ?? .owned }
        set { statusRaw = newValue.rawValue }
    }
    
    @Transient
    public var source: OutcomeSource {
        get { OutcomeSource(rawValue: sourceRaw) ?? .tagScan }
        set { sourceRaw = newValue.rawValue }
    }
    
    public init(
        id: String = UUID().uuidString,
        productID: String,
        productName: String,
        brand: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        status: OwnershipStatus = .owned,
        source: OutcomeSource = .tagScan,
        scoringStrategyIDs: [String] = [],
        recommendedScore: Double? = nil,
        captureItemID: String? = nil
    ) {
        self.id = id
        self.productID = productID
        self.productName = productName
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.scoringStrategyIDs = scoringStrategyIDs
        self.recommendedScore = recommendedScore
        self.captureItemID = captureItemID
        self.acquiredAt = Date()
    }
}
