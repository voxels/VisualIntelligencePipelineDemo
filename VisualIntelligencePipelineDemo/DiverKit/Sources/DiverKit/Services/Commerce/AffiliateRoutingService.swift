//
//  AffiliateRoutingService.swift
//  DiverKit
//
//  Routes product purchases through affiliate deep links.
//  Conforms to CommerceRouting protocol.
//
//  Ranks platforms by ethical match based on user's EthicalPolicy preferences
//  and generates affiliate-tracked URLs for supported platforms.
//

import Foundation
import DiverShared

/// Routes product purchases through affiliate deep links with ethical filtering.
/// Conforms to CommerceRouting protocol.
public final class AffiliateRoutingService: CommerceRouting, Sendable {
    
    /// Affiliate tag/ID per platform (stored in UserDefaults or via APIKeyService).
    private struct AffiliateConfig: Sendable {
        let platform: String
        let baseSearchURL: String
        let affiliateParam: String?
        let affiliateTag: String?
        let ethicalProfile: PlatformEthics
    }
    
    /// Known ethical profile for a commerce platform.
    private struct PlatformEthics: Sendable {
        let carbonIntensity: Float   // 0=low, 1=high
        let laborScore: Float        // 0=poor, 1=excellent
        let certifications: [String]
        let knownLaborViolations: Bool
    }
    
    /// Static platform registry with ethical profiles.
    private let platforms: [AffiliateConfig] = [
        AffiliateConfig(
            platform: "thrive_market",
            baseSearchURL: "https://thrivemarket.com/search?search=",
            affiliateParam: nil,
            affiliateTag: nil,
            ethicalProfile: PlatformEthics(carbonIntensity: 0.2, laborScore: 0.9, certifications: ["B Corp", "Carbon Neutral"], knownLaborViolations: false)
        ),
        AffiliateConfig(
            platform: "target",
            baseSearchURL: "https://www.target.com/s?searchTerm=",
            affiliateParam: nil,
            affiliateTag: nil,
            ethicalProfile: PlatformEthics(carbonIntensity: 0.5, laborScore: 0.6, certifications: [], knownLaborViolations: false)
        ),
        AffiliateConfig(
            platform: "amazon",
            baseSearchURL: "https://www.amazon.com/s?k=",
            affiliateParam: "tag",
            affiliateTag: nil,
            ethicalProfile: PlatformEthics(carbonIntensity: 0.7, laborScore: 0.3, certifications: [], knownLaborViolations: true)
        ),
        AffiliateConfig(
            platform: "bestbuy",
            baseSearchURL: "https://www.bestbuy.com/site/searchpage.jsp?st=",
            affiliateParam: nil,
            affiliateTag: nil,
            ethicalProfile: PlatformEthics(carbonIntensity: 0.5, laborScore: 0.5, certifications: ["Energy Star Partner"], knownLaborViolations: false)
        ),
        AffiliateConfig(
            platform: "ebay",
            baseSearchURL: "https://www.ebay.com/sch/i.html?_nkw=",
            affiliateParam: "mkcid",
            affiliateTag: nil,
            ethicalProfile: PlatformEthics(carbonIntensity: 0.3, laborScore: 0.5, certifications: [], knownLaborViolations: false)
        )
    ]
    
    public init() {}
    
    // MARK: - CommerceRouting
    
    public func affiliateLink(for product: ProductClassification, platform: String) async throws -> URL? {
        guard let config = platforms.first(where: { $0.platform == platform }) else {
            return nil
        }
        
        let searchTerm = product.barcode ?? product.name
        guard let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        var urlString = config.baseSearchURL + encoded
        
        // Append affiliate tag if configured
        if let param = config.affiliateParam, let tag = config.affiliateTag {
            urlString += "&\(param)=\(tag)"
        }
        
        return URL(string: urlString)
    }
    
    public func rankPlatforms(for product: ProductClassification, policy: EthicalPolicy) async throws -> [PlatformMatch] {
        var matches: [PlatformMatch] = []
        
        for config in platforms {
            // Build platform profile from known ethics data
            let profile: [String: Float] = [
                "carbon": config.ethicalProfile.carbonIntensity,
                "labor": config.ethicalProfile.laborScore,
                "laborViolations": config.ethicalProfile.knownLaborViolations ? 1.0 : 0.0,
                "price": 0.5,           // Default neutral; real data from pricing APIs
                "shipping": 0.5,
                "deliverySpeed": 0.5,
                "inStock": 0.8,
                "localPickup": 0.3,
                "returns": 0.5,
            ]
            
            // Delegate exclusion to the policy
            if policy.shouldExclude(
                platformProfile: profile,
                certifications: config.ethicalProfile.certifications
            ) {
                continue
            }
            
            // Score using the policy's dimensions
            var totalScore: Float = 0
            var totalWeight: Float = 0
            var reasons: [String] = []
            var dimensionScores: [String: Float] = [:]
            
            for dimension in policy.dimensions {
                let dimScore: Float
                
                switch dimension.name {
                case "carbon":
                    dimScore = 1.0 - config.ethicalProfile.carbonIntensity
                    if dimScore > 0.7 { reasons.append("Low carbon footprint") }
                case "labor":
                    dimScore = config.ethicalProfile.laborScore
                    if dimScore > 0.7 { reasons.append("Good labor practices") }
                case "certifications":
                    let certMatch = config.ethicalProfile.certifications.filter { cert in
                        policy.preferredCertifications.isEmpty ||
                        policy.preferredCertifications.contains(where: { cert.lowercased().contains($0.lowercased()) })
                    }
                    dimScore = certMatch.isEmpty ? 0 : 1.0
                    if !certMatch.isEmpty { reasons.append(contentsOf: certMatch) }
                case "preference":
                    dimScore = policy.platformPreferenceBonus(for: config.platform)
                    if dimScore > 0 { reasons.append("User preferred") }
                default:
                    // For dimensions not yet data-backed (price, speed, etc.)
                    // use the profile value if available, otherwise neutral 0.5
                    dimScore = profile[dimension.name] ?? 0.5
                }
                
                dimensionScores[dimension.name] = dimScore
                totalScore += dimScore * dimension.weight
                totalWeight += dimension.weight
            }
            
            let normalizedScore = totalWeight > 0 ? totalScore / totalWeight : 0
            
            // Generate affiliate URL
            let url = try? await affiliateLink(for: product, platform: config.platform)
            
            matches.append(PlatformMatch(
                platform: config.platform,
                matchScore: min(1.0, normalizedScore),
                affiliateURL: url,
                matchReasons: reasons,
                dimensionScores: dimensionScores
            ))
        }
        
        // Sort by match score, highest first
        return matches.sorted { $0.matchScore > $1.matchScore }
    }
}
