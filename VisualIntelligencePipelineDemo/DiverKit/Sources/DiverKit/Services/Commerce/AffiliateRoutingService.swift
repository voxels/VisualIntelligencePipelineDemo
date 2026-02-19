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
            // Skip platforms with labor violations if policy excludes them
            if policy.excludeLaborViolations && config.ethicalProfile.knownLaborViolations {
                continue
            }
            
            // Skip platforms above carbon threshold
            if config.ethicalProfile.carbonIntensity > policy.carbonThreshold {
                continue
            }
            
            // Calculate ethical match score
            var score: Float = 0
            var reasons: [String] = []
            
            // Carbon score contribution (lower is better)
            let carbonMatch = 1.0 - config.ethicalProfile.carbonIntensity
            score += carbonMatch * 0.3
            if carbonMatch > 0.7 { reasons.append("Low carbon footprint") }
            
            // Labor score contribution
            score += config.ethicalProfile.laborScore * 0.3
            if config.ethicalProfile.laborScore > 0.7 { reasons.append("Good labor practices") }
            
            // Certification match
            let certMatch = config.ethicalProfile.certifications.filter { cert in
                policy.preferredCertifications.isEmpty ||
                policy.preferredCertifications.contains(where: { cert.lowercased().contains($0.lowercased()) })
            }
            if !certMatch.isEmpty {
                score += 0.2
                reasons.append(contentsOf: certMatch)
            }
            
            // User preference ranking bonus
            if let rankIndex = policy.platformRanking.firstIndex(of: config.platform) {
                let rankBonus = Float(policy.platformRanking.count - rankIndex) / Float(max(policy.platformRanking.count, 1))
                score += rankBonus * 0.2
                reasons.append("User preferred")
            }
            
            // Generate affiliate URL
            let url = try? await affiliateLink(for: product, platform: config.platform)
            
            matches.append(PlatformMatch(
                platform: config.platform,
                ethicalMatchScore: min(1.0, score),
                affiliateURL: url,
                matchReasons: reasons
            ))
        }
        
        // Sort by ethical match score, highest first
        return matches.sorted { $0.ethicalMatchScore > $1.ethicalMatchScore }
    }
}
