import SwiftUI
import DiverKit

public struct ProductProfileView: View {
    let item: ProcessedItem
    @StateObject private var viewModel = ReferenceDetailViewModel()
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Core Commerce Data & AR Scores
            if item.productMetadata != nil || item.commerceContext != nil {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cart.fill")
                            .foregroundStyle(.green)
                        Text("Commerce Intelligence")
                            .font(.title3)
                            .bold()
                    }
                    
                    if let recommendations = item.commerceContext, let first = recommendations.first {
                        ProductScoreAttachment(
                            productName: first.option.productName,
                            compositeScore: first.compositeScore,
                            strategyScores: first.option.scores.map { ($0.strategyID.capitalized, $0.overallScore) },
                            recommendation: first.compositeScore >= 0.7 ? "Buy Now" :
                                first.compositeScore >= 0.4 ? "Consider" : "Wait"
                        )
                        
                        ProductScoreOverlayView(
                            recommendation: first,
                            allScores: first.option.scores,
                            insight: nil,
                            advisorySignal: nil,
                            advisoryExplanation: nil
                        )
                    }
                    
                    OwnershipButton(productName: item.displayTitle, barcode: item.productMetadata)
                        .padding(.vertical, 4)
                    
                    if !viewModel.scoreSnapshots.isEmpty {
                        ScoreHistoryChartView(snapshots: viewModel.scoreSnapshots, strategyID: "esg")
                            .frame(height: 200)
                    }
                    
                    // Nowcast Result
                    if let nowcast = item.nowcastContext {
                        HStack(spacing: 12) {
                            Image(systemName: nowcast.direction == .rising ? "arrow.up.right.circle.fill" :
                                    nowcast.direction == .falling ? "arrow.down.right.circle.fill" :
                                    "equal.circle.fill")
                                .font(.title2)
                                .foregroundStyle(nowcast.direction == .rising ? .green :
                                                    nowcast.direction == .falling ? .red : .secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Price Trend: \(nowcast.direction.rawValue.capitalized)")
                                    .font(.subheadline.weight(.medium))
                                Text("Confidence: \(Int(nowcast.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%+.1f%%", nowcast.projectedChange * 100))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(nowcast.projectedChange > 0 ? .red : .green)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    
                    if let platforms = item.affiliateContext, !platforms.isEmpty {
                        CommerceActionView(platforms: platforms)
                    }
                    
                    // Government Safety Alerts
                    if let gov = item.governmentContext, gov.hasConcerns {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Safety Alerts")
                                    .font(.subheadline.weight(.semibold))
                            }
                            
                            ForEach(gov.recalls) { recall in
                                HStack(alignment: .top) {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    VStack(alignment: .leading) {
                                        Text(recall.title)
                                            .font(.caption.weight(.medium))
                                        if let hazard = recall.hazard {
                                            Text(hazard)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            ForEach(gov.fdaAlerts) { alert in
                                HStack(alignment: .top) {
                                    Image(systemName: "cross.circle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    VStack(alignment: .leading) {
                                        Text("FDA \(alert.classification)")
                                            .font(.caption.weight(.medium))
                                        Text(alert.reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
                .background(Color(normalize(color: .secondarySystemGroupedBackground)))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // ESG Details
            if let esg = item.esgContext {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(.green)
                        Text("Product Details")
                            .font(.title3)
                            .bold()
                        Spacer()
                        Text(esg.source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let name = esg.genericName {
                        DetailRow(label: "Product", value: name)
                    }
                    if let qty = esg.quantity {
                        DetailRow(label: "Size", value: qty)
                    }
                    
                    HStack(spacing: 16) {
                        if let eco = esg.ecoScore {
                            ScoreBadge(label: "Eco-Score", value: eco.uppercased(), color: gradeColor(eco))
                        }
                        if let nutri = esg.nutriScore {
                            ScoreBadge(label: "Nutri-Score", value: nutri.uppercased(), color: gradeColor(nutri))
                        }
                        if let nova = esg.novaGroup {
                            ScoreBadge(label: "NOVA", value: "\(nova)/4", color: nova <= 2 ? .green : nova == 3 ? .orange : .red)
                        }
                        if let carbon = esg.carbonIntensity {
                            ScoreBadge(label: "CO₂", value: String(format: "%.1f", carbon), color: carbon < 2 ? .green : carbon < 5 ? .orange : .red)
                        }
                    }
                    
                    if let ingredients = esg.ingredientsText, !ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ingredients")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(ingredients)
                                .font(.caption)
                                .lineLimit(5)
                        }
                    }
                    
                    if !esg.allergens.isEmpty {
                        DetailRow(label: "Allergens", value: esg.allergens.joined(separator: ", "))
                    }
                    if !esg.traces.isEmpty {
                        DetailRow(label: "May contain", value: esg.traces.joined(separator: ", "))
                    }
                    
                    if let origin = esg.origins {
                        DetailRow(label: "Origin", value: origin)
                    }
                    if let mfg = esg.manufacturingPlaces {
                        DetailRow(label: "Made in", value: mfg)
                    }
                    if let packaging = esg.packagingText {
                        DetailRow(label: "Packaging", value: packaging)
                    }
                    
                    if !esg.certifications.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Certifications")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(esg.certifications, id: \.self) { cert in
                                    Text(cert)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.green.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                    }
                    
                    if !esg.nutriments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nutrition (per serving)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            let sorted = esg.nutriments.sorted { $0.key < $1.key }.prefix(8)
                            ForEach(Array(sorted), id: \.key) { key, value in
                                HStack {
                                    Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                    Spacer()
                                    Text(String(format: "%.1f", value))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    if !esg.stores.isEmpty {
                        DetailRow(label: "Available at", value: esg.stores.joined(separator: ", "))
                    }
                }
                .padding()
                .background(Color(normalize(color: .secondarySystemGroupedBackground)))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Product Search Preview
            if item.isProduct, let searchURL = item.productSearchURL {
                 VStack(alignment: .leading, spacing: 8) {
                     Text("Product Search Result")
                         .font(.headline)
                     
                     RichWebView(url: searchURL)
                        .frame(height: 350)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                 }
                 .padding()
                 .background(Color(normalize(color: .secondarySystemGroupedBackground)))
                 .cornerRadius(12)
                 .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .onAppear {
            if let barcode = item.productMetadata {
                viewModel.fetchScoreHistory(productID: barcode)
            }
        }
    }
    
    private func gradeColor(_ grade: String) -> Color {
        switch grade.lowercased() {
        case "a": return .green
        case "b": return .mint
        case "c": return .yellow
        case "d": return .orange
        case "e": return .red
        default: return .secondary
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }
}

private struct ScoreBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
