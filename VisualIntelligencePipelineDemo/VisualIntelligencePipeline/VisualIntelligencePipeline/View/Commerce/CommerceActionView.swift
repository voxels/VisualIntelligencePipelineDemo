//
//  CommerceActionView.swift
//  VisualIntelligencePipeline
//
//  Affiliate CTA (call-to-action) view showing ranked commerce platforms
//  with ethical match scores. Links open in Safari with affiliate tracking.
//

import SwiftUI
import DiverShared

/// Commerce platform CTA with ethical ranking.
struct CommerceActionView: View {
    let platforms: [PlatformMatch]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.green)
                Text("Where to Buy")
                    .font(.headline)
            }
            
            if platforms.isEmpty {
                Text("No matching platforms found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(platforms) { platform in
                    HStack(spacing: 12) {
                        // Platform icon
                        Image(systemName: platformIcon(platform.platform))
                            .font(.title3)
                            .foregroundStyle(platformColor(platform.platform))
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platformDisplayName(platform.platform))
                                .font(.subheadline.weight(.semibold))
                            
                            if !platform.matchReasons.isEmpty {
                                Text(platform.matchReasons.prefix(2).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Match score badge
                        Text("\(Int(platform.ethicalMatchScore * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(matchScoreColor(platform.ethicalMatchScore))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                matchScoreColor(platform.ethicalMatchScore).opacity(0.12),
                                in: Capsule()
                            )
                        
                        // Open link
                        if let url = platform.affiliateURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    
                    if platform.id != platforms.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func platformIcon(_ name: String) -> String {
        switch name {
        case "amazon": return "shippingbox.fill"
        case "target": return "target"
        case "bestbuy": return "desktopcomputer"
        case "ebay": return "bag.fill"
        case "thrive_market": return "leaf.fill"
        default: return "storefront.fill"
        }
    }
    
    private func platformDisplayName(_ name: String) -> String {
        switch name {
        case "amazon": return "Amazon"
        case "target": return "Target"
        case "bestbuy": return "Best Buy"
        case "ebay": return "eBay"
        case "thrive_market": return "Thrive Market"
        default: return name.capitalized
        }
    }
    
    private func platformColor(_ name: String) -> Color {
        switch name {
        case "amazon": return .orange
        case "target": return .red
        case "bestbuy": return .blue
        case "ebay": return .indigo
        case "thrive_market": return .green
        default: return .gray
        }
    }
    
    private func matchScoreColor(_ score: Float) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .orange }
        return .red
    }
}

#Preview {
    CommerceActionView(platforms: [
        PlatformMatch(platform: "thrive_market", ethicalMatchScore: 0.92, affiliateURL: URL(string: "https://thrivemarket.com"), matchReasons: ["B Corp", "Carbon Neutral"]),
        PlatformMatch(platform: "target", ethicalMatchScore: 0.65, affiliateURL: URL(string: "https://target.com"), matchReasons: ["Local pickup"]),
        PlatformMatch(platform: "amazon", ethicalMatchScore: 0.35, affiliateURL: URL(string: "https://amazon.com"), matchReasons: [])
    ])
    .padding()
}
