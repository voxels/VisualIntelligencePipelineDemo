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
            if let commerce = item.commerceContext {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cart.fill")
                            .foregroundStyle(.blue)
                        Text("Commerce Engine")
                            .font(.title3)
                            .bold()
                        Spacer()
                    }
                    
                    // Ownership Actions
                    OwnershipButton(productName: item.displayTitle, barcode: item.productMetadata)
                        .padding(.vertical, 4)
                    
                    // Affiliate Routing Block
                    if let platforms = item.affiliateContext, !platforms.isEmpty {
                        CommerceActionView(platforms: platforms)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Commerce Charts Context
            if item.productMetadata != nil {
                VStack(alignment: .leading, spacing: 16) {
                    ScoreHistoryChartView(snapshots: viewModel.scoreSnapshots, strategyID: "esg")
                        .frame(height: 200)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
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
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
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
