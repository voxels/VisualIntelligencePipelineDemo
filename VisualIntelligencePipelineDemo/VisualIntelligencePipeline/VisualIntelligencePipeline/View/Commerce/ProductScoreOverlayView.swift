//
//  ProductScoreOverlayView.swift
//  VisualIntelligencePipeline
//
//  Created by Antigravity on 02/19/26.
//

import SwiftUI
import DiverShared

/// Multi-strategy overlay card showing per-engine scores, timing recommendation,
/// and ownership controls. Renders `[ProductScore]` from all active strategies.
struct ProductScoreOverlayView: View {
    let recommendation: RankedRecommendation
    let allScores: [ProductScore]
    let insight: String?
    let advisorySignal: String? // "buy", "wait", "alternatives"
    let advisoryExplanation: String?
    var onOwnThis: (() -> Void)? = nil
    
    @State private var selectedStrategy: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Product name + brand + composite score
            headerSection
            
            Divider()
            
            // Timing Recommendation (independent of strategy scores)
            if let signal = advisorySignal, let explanation = advisoryExplanation {
                timingPill(signal: signal, explanation: explanation)
                Divider()
            }
            
            // Strategy Score Tabs
            if !allScores.isEmpty {
                strategyTabs
                
                // Selected strategy dimensions
                if let selected = selectedScore {
                    strategyDetail(selected)
                }
            }
            
            // Product Insight (SLM-generated summary)
            if let insight, !insight.isEmpty {
                Text(insight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            // Ownership button
            if let onOwnThis {
                Divider()
                Button(action: onOwnThis) {
                    Label("I Own This", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear {
            selectedStrategy = allScores.first?.strategyID
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.option.productName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let brand = recommendation.option.brand {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(brand)
                            .font(.caption)
                        if recommendation.brandAffinity > 0.6 {
                            Text("• Preferred")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            compositeScoreBadge
        }
    }
    
    private func timingPill(signal: String, explanation: String) -> some View {
        HStack(spacing: 8) {
            signalIcon(signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(signalLabel(signal))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(signalColor(signal))
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var strategyTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allScores, id: \.strategyID) { score in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedStrategy = score.strategyID
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(strategyDisplayName(score.strategyID))
                                .font(.caption2.weight(.semibold))
                            Text("\(Int(score.overallScore * 100))%")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(scoreColor(score.overallScore))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedStrategy == score.strategyID
                                ? scoreColor(score.overallScore).opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func strategyDetail(_ score: ProductScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(score.dimensions, id: \.name) { dim in
                dimensionRow(dim)
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - Subviews
    
    private var selectedScore: ProductScore? {
        allScores.first { $0.strategyID == selectedStrategy }
    }
    
    private var compositeScoreBadge: some View {
        ZStack {
            Circle()
                .fill(scoreColor(recommendation.compositeScore).opacity(0.15))
                .frame(width: 48, height: 48)
            VStack(spacing: 0) {
                Text("\(Int(recommendation.compositeScore * 100))")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(scoreColor(recommendation.compositeScore))
                Text("score")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func dimensionRow(_ dim: ScoringDimension) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dim.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Text(dim.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)
                    Capsule()
                        .fill(scoreColor(dim.score))
                        .frame(width: max(4, geo.size.width * CGFloat(dim.score)), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
    
    // MARK: - Helpers
    
    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 0..<0.3: return .red
        case 0.3..<0.6: return .orange
        case 0.6..<0.8: return .yellow
        default: return .green
        }
    }
    
    private func strategyDisplayName(_ id: String) -> String {
        switch id {
        case "esg": return "Ethics"
        case "brand": return "Brand"
        case "value": return "Value"
        case "durability": return "Durability"
        case "social": return "Social"
        case "health": return "Health"
        case "totalcost": return "Total Cost"
        default: return id.capitalized
        }
    }
    
    private func signalIcon(_ signal: String) -> some View {
        Group {
            switch signal {
            case "buy":
                Image(systemName: "clock.badge.checkmark.fill")
                    .foregroundStyle(.green)
            case "wait":
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
            case "alternatives":
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.blue)
            default:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3)
    }
    
    private func signalLabel(_ signal: String) -> String {
        switch signal {
        case "buy": return "Buy Now"
        case "wait": return "Wait"
        case "alternatives": return "Consider Alternatives"
        default: return "Assessing..."
        }
    }
    
    private func signalColor(_ signal: String) -> Color {
        switch signal {
        case "buy": return .green
        case "wait": return .orange
        case "alternatives": return .blue
        default: return .secondary
        }
    }
}

#Preview {
    let esgScore = ProductScore(
        strategyID: "esg",
        overallScore: 0.72,
        dimensions: [
            ScoringDimension(name: "Carbon Intensity", score: 0.65, weight: 0.4, source: "Climate TRACE", explanation: "2.3 kg CO₂e per unit"),
            ScoringDimension(name: "Data Quality", score: 0.75, weight: 0.3, source: "Open Food Facts", explanation: "Tier 2 — company reported"),
            ScoringDimension(name: "Certifications", score: 0.66, weight: 0.2, source: "Open Food Facts", explanation: "Rainforest Alliance, Fair Trade"),
            ScoringDimension(name: "Eco-Score", score: 0.75, weight: 0.1, source: "Open Food Facts", explanation: "Eco-Score: B"),
        ]
    )
    
    let brandScore = ProductScore(
        strategyID: "brand",
        overallScore: 0.85,
        dimensions: [
            ScoringDimension(name: "Brand Match", score: 0.9, weight: 0.5, source: "User History", explanation: "Green & Black's — 12 interactions"),
            ScoringDimension(name: "Category Familiarity", score: 0.7, weight: 0.3, source: "User History", explanation: "4 known brands in food"),
            ScoringDimension(name: "Preference Strength", score: 0.8, weight: 0.2, source: "User History", explanation: "38% of your brand interactions"),
        ]
    )
    
    let durabilityScore = ProductScore(
        strategyID: "durability",
        overallScore: 0.1,
        dimensions: [
            ScoringDimension(name: "Category Longevity", score: 0.1, weight: 0.3, source: "Category Analysis", explanation: "Consumable: single-use product"),
        ]
    )
    
    let valueScore = ProductScore(
        strategyID: "value",
        overallScore: 0.6,
        dimensions: [
            ScoringDimension(name: "Price Trend", score: 0.6, weight: 0.4, source: "Price Analysis", explanation: "Prices stable"),
            ScoringDimension(name: "Price Position", score: 0.5, weight: 0.4, source: "Price Analysis", explanation: "Price comparison data not yet available"),
        ]
    )
    
    let option = PurchaseOption(
        platform: "detected",
        productName: "Organic Dark Chocolate Bar",
        brand: "Green & Black's",
        price: 4.99,
        currency: "USD",
        scores: [esgScore, brandScore, durabilityScore, valueScore],
        affiliateURL: URL(string: "https://example.com")!
    )
    
    let recommendation = RankedRecommendation(
        option: option,
        brandAffinity: 0.82,
        compositeScore: 0.74
    )
    
    ProductScoreOverlayView(
        recommendation: recommendation,
        allScores: [esgScore, brandScore, durabilityScore, valueScore],
        insight: "Well-regarded sustainable chocolate with strong certifications. Rainforest Alliance sourcing adds credibility.",
        advisorySignal: "buy",
        advisoryExplanation: "Pricing stable with strong sustainability profile.",
        onOwnThis: { print("Owned!") }
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
