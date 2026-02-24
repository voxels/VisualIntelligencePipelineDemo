//
//  CommerceActionView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import DiverShared

public struct CommerceActionView: View {
    public let platforms: [PlatformMatch]
    public init(platforms: [PlatformMatch]) { self.platforms = platforms }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cart.fill").foregroundStyle(.green)
                Text("Where to Buy").font(.headline)
            }
            if platforms.isEmpty {
                Text("No matching platforms found").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(platforms) { platform in
                    HStack(spacing: 12) {
                        Image(systemName: platformIcon(platform.platform))
                            .font(.title3).foregroundStyle(platformColor(platform.platform)).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platformDisplayName(platform.platform)).font(.subheadline.weight(.semibold))
                            if !platform.matchReasons.isEmpty {
                                Text(platform.matchReasons.prefix(2).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(platform.ethicalMatchScore * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(matchScoreColor(platform.ethicalMatchScore))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(matchScoreColor(platform.ethicalMatchScore).opacity(0.12), in: Capsule())
                        if let url = platform.affiliateURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    if platform.id != platforms.last?.id { Divider() }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func platformIcon(_ name: String) -> String {
        switch name {
        case "amazon": "shippingbox.fill"; case "target": "target"
        case "bestbuy": "desktopcomputer"; case "ebay": "bag.fill"
        case "thrive_market": "leaf.fill"; default: "storefront.fill"
        }
    }
    private func platformDisplayName(_ name: String) -> String {
        switch name {
        case "amazon": "Amazon"; case "target": "Target"; case "bestbuy": "Best Buy"
        case "ebay": "eBay"; case "thrive_market": "Thrive Market"; default: name.capitalized
        }
    }
    private func platformColor(_ name: String) -> Color {
        switch name {
        case "amazon": .orange; case "target": .red; case "bestbuy": .blue
        case "ebay": .indigo; case "thrive_market": .green; default: .gray
        }
    }
    private func matchScoreColor(_ score: Float) -> Color {
        score >= 0.7 ? .green : score >= 0.4 ? .orange : .red
    }
}
