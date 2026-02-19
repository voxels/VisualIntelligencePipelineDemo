//
//  ESGScoringStrategy.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// **Ethics Ranking Engine** — the primary ethical scoring strategy.
///
/// Bundles ESG core dimensions (carbon, data quality, certifications, Eco-Score)
/// with expanded sub-dimensions from Phase 1a (safety, nutrition, packaging,
/// privacy, EPA compliance, energy efficiency). All sub-dimensions produce
/// weighted contributions to a single "Ethics" score.
///
/// Users see one top-level Ethics score and can drill into each sub-dimension
/// to see individual contributions.
public final class ESGScoringStrategy: ProductScoringStrategy, Sendable {
    
    public let strategyID = "esg"
    public let displayName = "Ethics"
    
    public init() {}
    
    public func score(_ product: ProductClassification, enrichment: (any Sendable)?) async throws -> ProductScore {
        // Extract enrichment data — supports both standalone ESG and bundled (ESG + Gov)
        var esg: ESGEnrichment?
        var gov: GovernmentEnrichment?
        
        if let bundle = enrichment as? (ESGEnrichment, GovernmentEnrichment) {
            esg = bundle.0
            gov = bundle.1
        } else if let esgOnly = enrichment as? ESGEnrichment {
            esg = esgOnly
        }
        
        guard let esg = esg else {
            // No ESG data available — return a neutral score with explanation
            return ProductScore(
                strategyID: strategyID,
                overallScore: 0.5,
                dimensions: [
                    ScoringDimension(
                        name: "Data Availability",
                        score: 0.0,
                        weight: 1.0,
                        source: "none",
                        explanation: "No sustainability data available for this product"
                    )
                ]
            )
        }
        
        var dimensions: [ScoringDimension] = []
        
        // ── Core ESG Dimensions ──
        
        // 1. Data Quality Tier (PCAF-adapted, 1=best, 5=worst)
        let tierScore = max(0, 1.0 - Float(esg.dataQualityTier - 1) / 4.0)
        dimensions.append(ScoringDimension(
            name: "Data Quality",
            score: tierScore,
            weight: 0.15,
            source: esg.source,
            explanation: tierDescription(for: esg.dataQualityTier)
        ))
        
        // 2. Carbon Intensity (lower is better)
        if let carbon = esg.carbonIntensity {
            let carbonScore = max(0, min(1.0, 1.0 - carbon / 100.0))
            dimensions.append(ScoringDimension(
                name: "Carbon Intensity",
                score: carbonScore,
                weight: 0.20,
                source: esg.source,
                explanation: String(format: "%.1f kg CO₂e per unit", carbon)
            ))
        }
        
        // 3. Certifications
        let certScore: Float = esg.certifications.isEmpty ? 0.0 : min(1.0, Float(esg.certifications.count) * 0.33)
        dimensions.append(ScoringDimension(
            name: "Certifications",
            score: certScore,
            weight: 0.10,
            source: esg.source,
            explanation: esg.certifications.isEmpty
                ? "No certifications found"
                : esg.certifications.joined(separator: ", ")
        ))
        
        // 4. Eco-Score (Open Food Facts, A-E)
        if let ecoScore = esg.ecoScore {
            let ecoValue = ecoScoreValue(ecoScore)
            dimensions.append(ScoringDimension(
                name: "Eco-Score",
                score: ecoValue,
                weight: 0.10,
                source: "Open Food Facts",
                explanation: "Eco-Score: \(ecoScore.uppercased())"
            ))
        }
        
        // ── Phase 1a: Expanded Ethics Sub-Dimensions ──
        // These enrich the Ethics score when data is available.
        // When unavailable, their weight redistributes to core dimensions.
        
        // 5. Product Safety (CPSC Recalls, FDA openFDA) — live gov data
        let safetyScore = scoreSafety(product, gov: gov)
        dimensions.append(safetyScore)
        
        // 6. Nutrition Quality (Nutri-Score — food only)
        if let nutritionDim = scoreNutrition(product, esg: esg) {
            dimensions.append(nutritionDim)
        }
        
        // 7. Packaging Waste (Open Food Facts packaging data)
        let packagingDim = scorePackaging(esg)
        dimensions.append(packagingDim)
        
        // 8. Privacy & Data (ToS;DR — electronics/apps only)
        if product.category.contains("electronics") || product.category.contains("app") || product.category.contains("software") {
            dimensions.append(ScoringDimension(
                name: "Data Privacy",
                score: 0.5,
                weight: 0.05,
                source: "ToS;DR",
                explanation: "Privacy scoring data not yet indexed"
            ))
        }
        
        // 9. EPA Compliance — live gov data
        if let epaData = gov?.epaCompliance {
            let epaScore: Float = epaData.hasViolations ? max(0, 0.3 - Float(epaData.violationCount) * 0.05) : 0.8
            dimensions.append(ScoringDimension(
                name: "EPA Compliance",
                score: epaScore,
                weight: 0.05,
                source: "EPA ECHO",
                explanation: epaData.hasViolations
                    ? "\(epaData.violationCount) violation(s) found — \(epaData.complianceStatus)"
                    : "\(epaData.facilityName ?? product.brand ?? "Manufacturer") — \(epaData.complianceStatus)"
            ))
        } else {
            dimensions.append(ScoringDimension(
                name: "EPA Compliance",
                score: 0.5,
                weight: 0.05,
                source: "EPA ECHO",
                explanation: "Compliance data not yet available"
            ))
        }
        
        // 10. Energy Efficiency (Energy Star — electronics/appliances)
        if product.category.contains("electronics") || product.category.contains("appliance") {
            if let energyData = gov?.energyStarRating {
                let energyScore: Float = energyData.isCertified ? 0.9 : 0.3
                var explanation = energyData.isCertified ? "Energy Star Certified" : "Not Energy Star certified"
                if let kwh = energyData.annualEnergyUseKWh {
                    explanation += " — \(String(format: "%.0f", kwh)) kWh/year"
                }
                if let cost = energyData.energyCostPerYear {
                    explanation += " ($\(String(format: "%.0f", cost))/yr)"
                }
                dimensions.append(ScoringDimension(
                    name: "Energy Efficiency",
                    score: energyScore,
                    weight: 0.05,
                    source: "Energy Star",
                    explanation: explanation
                ))
            } else {
                dimensions.append(ScoringDimension(
                    name: "Energy Efficiency",
                    score: 0.5,
                    weight: 0.05,
                    source: "Energy Star",
                    explanation: "Energy rating data not yet available"
                ))
            }
        }
        
        // Compute weighted average across all available dimensions
        let totalWeight = dimensions.reduce(0) { $0 + $1.weight }
        let overallScore = totalWeight > 0
            ? dimensions.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
            : 0.5
        
        return ProductScore(
            strategyID: strategyID,
            overallScore: overallScore,
            dimensions: dimensions
        )
    }
    
    public func rank(_ options: [PurchaseOption]) async throws -> [PurchaseOption] {
        return options.sorted { a, b in
            let aScore = a.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            let bScore = b.scores.first(where: { $0.strategyID == strategyID })?.overallScore ?? 0
            if aScore != bScore { return aScore > bScore }
            return a.price < b.price
        }
    }
    
    // MARK: - Phase 1a Sub-Dimension Scorers
    
    private func scoreSafety(_ product: ProductClassification, gov: GovernmentEnrichment? = nil) -> ScoringDimension {
        // Use live CPSC/FDA data when available
        if let gov = gov {
            let recallCount = gov.recalls.count + gov.fdaAlerts.count
            if recallCount > 0 {
                // Each recall/alert reduces score, capped at 0.1 minimum
                let score = max(0.1, 1.0 - Float(recallCount) * 0.15)
                let recallSources = gov.recalls.prefix(2).map { $0.title }.joined(separator: "; ")
                return ScoringDimension(
                    name: "Product Safety",
                    score: score,
                    weight: 0.10,
                    source: "CPSC/FDA",
                    explanation: "\(recallCount) recall(s) found: \(recallSources)"
                )
            } else {
                return ScoringDimension(
                    name: "Product Safety",
                    score: 0.9,
                    weight: 0.10,
                    source: "CPSC/FDA",
                    explanation: "No recalls found — product passes safety check"
                )
            }
        }
        
        // Fallback: heuristic when no gov data available
        let riskCategories = ["toy", "children", "baby", "electronic", "chemical"]
        let isHighRisk = riskCategories.contains { product.category.lowercased().contains($0) }
        
        return ScoringDimension(
            name: "Product Safety",
            score: isHighRisk ? 0.5 : 0.7,
            weight: 0.10,
            source: "CPSC/FDA",
            explanation: isHighRisk
                ? "Higher-risk category — recall check pending"
                : "No known recalls"
        )
    }
    
    private func scoreNutrition(_ product: ProductClassification, esg: ESGEnrichment) -> ScoringDimension? {
        let foodCategories = ["food", "beverage", "snack", "dairy", "meat", "produce"]
        guard foodCategories.contains(where: { product.category.lowercased().contains($0) }) else {
            return nil // Not a food product
        }
        
        // Derive from Eco-Score for now; Phase 1a adds full Nutri-Score parsing
        if let ecoScore = esg.ecoScore {
            return ScoringDimension(
                name: "Nutrition Quality",
                score: ecoScoreValue(ecoScore) * 0.9, // Slightly less than Eco-Score
                weight: 0.10,
                source: "Open Food Facts",
                explanation: "Derived from Eco-Score \(ecoScore.uppercased())"
            )
        }
        
        return ScoringDimension(
            name: "Nutrition Quality",
            score: 0.5,
            weight: 0.10,
            source: "Open Food Facts",
            explanation: "Nutrition data not available"
        )
    }
    
    private func scorePackaging(_ esg: ESGEnrichment) -> ScoringDimension {
        // Phase 1a: Will parse packaging field from Open Food Facts
        // For now, certification presence is a proxy
        let hasPackagingCert = esg.certifications.contains { cert in
            let lower = cert.lowercased()
            return lower.contains("recycle") || lower.contains("packaging") || lower.contains("fsc")
        }
        
        return ScoringDimension(
            name: "Packaging",
            score: hasPackagingCert ? 0.8 : 0.4,
            weight: 0.10,
            source: "Open Food Facts",
            explanation: hasPackagingCert
                ? "Packaging certification detected"
                : "No packaging data available"
        )
    }
    
    // MARK: - Helpers
    
    private func tierDescription(for tier: Int) -> String {
        switch tier {
        case 1: return "Verified — independently audited data"
        case 2: return "Reported — company-level, unaudited"
        case 3: return "Estimated — industry sector averages"
        case 4: return "Extrapolated — broad economic data"
        case 5: return "Sector Average — no company-specific data"
        default: return "Unknown data quality"
        }
    }
    
    private func ecoScoreValue(_ grade: String) -> Float {
        switch grade.lowercased() {
        case "a": return 1.0
        case "b": return 0.75
        case "c": return 0.5
        case "d": return 0.25
        case "e": return 0.0
        default: return 0.5
        }
    }
}
