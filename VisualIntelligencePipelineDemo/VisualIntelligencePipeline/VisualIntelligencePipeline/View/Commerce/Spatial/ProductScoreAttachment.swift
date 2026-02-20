//
//  ProductScoreAttachment.swift
//  VisualIntelligencePipeline
//
//  SwiftUI spatial attachment showing a product score card in AR space.
//  Designed to float near detected products as a RealityKit attachment.
//  Works on both iPadOS and visionOS.
//

import SwiftUI

/// Spatial score card attachment for AR overlay.
/// Displays composite score, strategy breakdown, and recommendation.
struct ProductScoreAttachment: View {
    let productName: String
    let compositeScore: Float
    let strategyScores: [(name: String, score: Float)]
    let recommendation: String
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Composite score header
            HStack {
                VStack(alignment: .leading) {
                    Text(productName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(recommendation)
                        .font(.caption)
                        .foregroundStyle(recommendationColor)
                }
                
                Spacer()
                
                // Score ring
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(compositeScore))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(compositeScore * 100))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                .frame(width: 52, height: 52)
            }
            
            // Strategy breakdown (expandable)
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(strategyScores, id: \.name) { strategy in
                        HStack {
                            Text(strategy.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.quaternary)
                                    Capsule()
                                        .fill(barColor(strategy.score))
                                        .frame(width: geo.size.width * CGFloat(strategy.score))
                                }
                            }
                            .frame(width: 80, height: 6)
                            
                            Text("\(Int(strategy.score * 100))%")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        }
    }
    
    private var scoreColor: Color {
        if compositeScore >= 0.7 { return .green }
        if compositeScore >= 0.4 { return .orange }
        return .red
    }
    
    private var recommendationColor: Color {
        switch recommendation.lowercased() {
        case let r where r.contains("buy"): return .green
        case let r where r.contains("wait"): return .orange
        default: return .secondary
        }
    }
    
    private func barColor(_ score: Float) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .orange }
        return .red
    }
}

#Preview {
    ProductScoreAttachment(
        productName: "Organic Coffee Beans",
        compositeScore: 0.78,
        strategyScores: [
            ("Ethics", 0.85),
            ("Value", 0.72),
            ("Health", 0.90),
            ("Durability", 0.55),
        ],
        recommendation: "Buy Now"
    )
    .padding(40)
}
