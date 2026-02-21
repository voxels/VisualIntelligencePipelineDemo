//
//  AffiliateRoutingService.swift
//  DiverKit
//
//  Routes product purchases through affiliate deep links.
//  Conforms to CommerceRouting protocol.
//
//  Ranks platforms by ethical match based on user's EthicalPolicy preferences
//  and generates affiliate-tracked URLs for supported platforms.
//  Affiliate tags are loaded from APIKeyService (CloudKit-backed, syncs across devices).
//

import Foundation
import DiverShared

/// Routes product purchases through affiliate deep links with ethical filtering.
/// Conforms to CommerceRouting protocol.
///
/// Affiliate tags are loaded from `APIKeyService` (CloudKit private database)
/// at init time. Configure tags in Settings > API Keys.
public final class AffiliateRoutingService: CommerceRouting, Sendable {
    
    /// Per-platform config with ethical profile and affiliate URL builder.
    private struct AffiliateConfig: Sendable {
        let platform: String
        let affiliateTag: String?
        let ethicalProfile: PlatformEthics
        let buildURL: @Sendable (String, String?) -> URL?
    }
    
    /// Known ethical profile for a commerce platform.
    private struct PlatformEthics: Sendable {
        let carbonIntensity: Float   // 0=low, 1=high
        let laborScore: Float        // 0=poor, 1=excellent
        let certifications: [String]
        let knownLaborViolations: Bool
    }
    
    /// Platform registry — built at init with live affiliate tags from CloudKit cache.
    private let platforms: [AffiliateConfig]
    
    public init() {
        let apiKeys = APIKeyService()
        
        // Load affiliate tags from CloudKit cache (populated by prefetchKeys on app launch).
        // Returns nil if user hasn't configured a tag — links still work, just unattributed.
        let amazonTag = apiKeys.retrieve(for: .amazonAssociates)
        let ebayTag = apiKeys.retrieve(for: .ebayPartnerNetwork)
        let targetTag = apiKeys.retrieve(for: .targetPartners)
        let bestBuyTag = apiKeys.retrieve(for: .bestBuyAffiliate)
        let thriveTag = apiKeys.retrieve(for: .thriveMarketReferral)
        
        self.platforms = [
            // --- Thrive Market (B Corp, highest ethical score) ---
            AffiliateConfig(
                platform: "thrive_market",
                affiliateTag: thriveTag,
                ethicalProfile: PlatformEthics(carbonIntensity: 0.2, laborScore: 0.9, certifications: ["B Corp", "Carbon Neutral"], knownLaborViolations: false),
                buildURL: { searchTerm, tag in
                    var urlStr = "https://thrivemarket.com/search?search=\(searchTerm)"
                    if let tag { urlStr += "&refer=\(tag)" }
                    return URL(string: urlStr)
                }
            ),
            // --- Target (Impact Radius affiliate program) ---
            AffiliateConfig(
                platform: "target",
                affiliateTag: targetTag,
                ethicalProfile: PlatformEthics(carbonIntensity: 0.5, laborScore: 0.6, certifications: [], knownLaborViolations: false),
                buildURL: { searchTerm, tag in
                    var urlStr = "https://www.target.com/s?searchTerm=\(searchTerm)"
                    if let tag { urlStr += "&afid=\(tag)" }
                    return URL(string: urlStr)
                }
            ),
            // --- Amazon (Amazon Associates) ---
            AffiliateConfig(
                platform: "amazon",
                affiliateTag: amazonTag,
                ethicalProfile: PlatformEthics(carbonIntensity: 0.7, laborScore: 0.3, certifications: [], knownLaborViolations: true),
                buildURL: { searchTerm, tag in
                    var urlStr = "https://www.amazon.com/s?k=\(searchTerm)"
                    if let tag { urlStr += "&tag=\(tag)" }
                    return URL(string: urlStr)
                }
            ),
            // --- Best Buy (Impact Radius / CJ Affiliate) ---
            AffiliateConfig(
                platform: "bestbuy",
                affiliateTag: bestBuyTag,
                ethicalProfile: PlatformEthics(carbonIntensity: 0.5, laborScore: 0.5, certifications: ["Energy Star Partner"], knownLaborViolations: false),
                buildURL: { searchTerm, tag in
                    var urlStr = "https://www.bestbuy.com/site/searchpage.jsp?st=\(searchTerm)"
                    if let tag { urlStr += "&irclickid=\(tag)" }
                    return URL(string: urlStr)
                }
            ),
            // --- eBay (eBay Partner Network) ---
            AffiliateConfig(
                platform: "ebay",
                affiliateTag: ebayTag,
                ethicalProfile: PlatformEthics(carbonIntensity: 0.3, laborScore: 0.5, certifications: [], knownLaborViolations: false),
                buildURL: { searchTerm, tag in
                    var urlStr = "https://www.ebay.com/sch/i.html?_nkw=\(searchTerm)&mkcid=1"
                    if let tag { urlStr += "&campid=\(tag)" }
                    return URL(string: urlStr)
                }
            )
        ]
    }
    
    // MARK: - CommerceRouting
    
    public func affiliateLink(for product: ProductClassification, platform: String) async throws -> URL? {
        guard let config = platforms.first(where: { $0.platform == platform }) else {
            return nil
        }
        
        let searchTerm = product.barcode ?? product.name
        guard let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        return config.buildURL(encoded, config.affiliateTag)
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
