//
//  ProductScoreAttachment.swift
//  VisualIntelligencePipeline
//
//  SwiftUI spatial attachment showing a product score card in AR space.
//  Designed to float near detected products as a RealityKit attachment.
//  Works on both iPadOS and visionOS.
//

import SwiftUI
import Charts
import DiverShared

/// Spatial score card attachment for AR overlay.
/// Displays composite score, strategy breakdown, recommendation, and intelligence summary.
struct ProductScoreAttachment: View {
    let productName: String
    let brand: String?
    let compositeScore: Float
    let strategyScores: [(name: String, score: Float)]
    let recommendation: String
    let summary: String?
    let priceTrajectory: PriceTrajectory?
    var onOwnershipChange: ((String?, String, String?, OwnershipStatus) -> Void)?
    
    @State private var isExpanded = false
    @State private var selectedStatus: OwnershipStatus? = nil
    
    init(
        productName: String,
        brand: String? = nil,
        compositeScore: Float,
        strategyScores: [(name: String, score: Float)],
        recommendation: String,
        summary: String? = nil,
        priceTrajectory: PriceTrajectory? = nil,
        onOwnershipChange: ((String?, String, String?, OwnershipStatus) -> Void)? = nil
    ) {
        self.productName = productName
        self.brand = brand
        self.compositeScore = compositeScore
        self.strategyScores = strategyScores
        self.recommendation = recommendation
        self.summary = summary
        self.priceTrajectory = priceTrajectory
        self.onOwnershipChange = onOwnershipChange
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Composite score header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(productName)
                        .font(.headline)
                        .lineLimit(2)
                    if let brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            
            // Intelligence summary
            if let summary, !summary.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Strategy breakdown (expandable)
            if isExpanded {
                // Price trend sparkline
                if let trajectory = priceTrajectory, !trajectory.dataPoints.isEmpty {
                    HStack(spacing: 8) {
                        // Sparkline chart
                        Chart(trajectory.dataPoints, id: \.date) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Price", NSDecimalNumber(decimal: point.value).doubleValue)
                            )
                            .foregroundStyle(trendColor(trajectory.projectedDirection))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            
                            if point.isProjected {
                                AreaMark(
                                    x: .value("Date", point.date),
                                    y: .value("Price", NSDecimalNumber(decimal: point.value).doubleValue)
                                )
                                .foregroundStyle(trendColor(trajectory.projectedDirection).opacity(0.1))
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(width: 100, height: 32)
                        
                        // Trend pill
                        HStack(spacing: 4) {
                            Image(systemName: trendIcon(trajectory.projectedDirection))
                                .font(.caption2)
                            Text(trendLabel(trajectory.projectedDirection))
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(trendColor(trajectory.projectedDirection))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(trendColor(trajectory.projectedDirection).opacity(0.12), in: Capsule())
                        
                        Spacer()
                        
                        Text("\(Int(trajectory.confidenceInterval * 100))% conf")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                
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
            
            // Ownership action buttons (always visible)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        selectedStatus = .wishlisted
                    }
                    onOwnershipChange?(nil, productName, brand, .wishlisted)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedStatus == .wishlisted ? "heart.fill" : "heart")
                            .font(.caption2)
                        Text("Want")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedStatus == .wishlisted ? Color.pink.opacity(0.2) : Color.secondary.opacity(0.1),
                        in: Capsule()
                    )
                    .foregroundStyle(selectedStatus == .wishlisted ? .pink : .secondary)
                }
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        selectedStatus = .owned
                    }
                    onOwnershipChange?(nil, productName, brand, .owned)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedStatus == .owned ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption2)
                        Text("Own")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedStatus == .owned ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1),
                        in: Capsule()
                    )
                    .foregroundStyle(selectedStatus == .owned ? .green : .secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .frame(width: 280)
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
    
    private func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .rising: return .red
        case .falling: return .green
        case .stable: return .blue
        }
    }
    
    private func trendIcon(_ direction: TrendDirection) -> String {
        switch direction {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    private func trendLabel(_ direction: TrendDirection) -> String {
        switch direction {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .stable: return "Stable"
        }
    }
}

#Preview {
    ProductScoreAttachment(
        productName: "Organic Dark Chocolate Bar",
        brand: "Green & Black's",
        compositeScore: 0.78,
        strategyScores: [
            ("Ethics", 0.85),
            ("Health", 0.72),
            ("Safety", 0.90),
        ],
        recommendation: "✅ Recommended — strong scores",
        summary: "Eco-Score B (good) · Certified: Fair Trade, Organic · NOVA 2/4 processing · via Open Food Facts"
    )
    .padding(40)
}
