//
//  EthicalPolicySettings.swift
//  DiverKit
//
//  SwiftData model for user's ethical purchasing preferences.
//  Syncs across devices via CloudKit.
//

import Foundation
import SwiftData

/// Persisted ethical policy settings for commerce scoring and routing.
/// Syncs via CloudKit for cross-device consistency.
///
/// This is a singleton model — only one instance should exist per user.
/// Use `EthicalPolicySettings.current(in:)` to fetch or create the instance.
@Model
public final class EthicalPolicySettings {
    
    /// Carbon footprint filter threshold (0.0 = strictest, 1.0 = no filter).
    public var carbonThreshold: Float = 0.5
    
    /// Whether to exclude platforms with documented labor violations.
    public var excludeLaborViolations: Bool = false
    
    /// Preferred certifications (e.g., "B Corp", "Fair Trade", "USDA Organic").
    public var certifications: [String] = []
    
    /// Preferred platform ordering for commerce routing.
    /// First platform gets highest priority in recommendations.
    public var platformRanking: [String] = ["thrive_market", "target", "bestbuy", "ebay", "amazon"]
    
    /// Timestamp for last modification (used for CloudKit conflict resolution).
    public var updatedAt: Date = Date()
    
    public init(
        carbonThreshold: Float = 0.5,
        excludeLaborViolations: Bool = false,
        certifications: [String] = [],
        platformRanking: [String] = ["thrive_market", "target", "bestbuy", "ebay", "amazon"]
    ) {
        self.carbonThreshold = carbonThreshold
        self.excludeLaborViolations = excludeLaborViolations
        self.certifications = certifications
        self.platformRanking = platformRanking
        self.updatedAt = Date()
    }
    
    /// Fetch or create the singleton settings instance.
    public static func current(in context: ModelContext) -> EthicalPolicySettings {
        var descriptor = FetchDescriptor<EthicalPolicySettings>()
        descriptor.fetchLimit = 1
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        let settings = EthicalPolicySettings()
        context.insert(settings)
        try? context.save()
        return settings
    }
}
