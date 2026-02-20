//
//  OwnedProductsView.swift
//  VisualIntelligencePipeline
//
//  Displays the user's owned products grouped by brand.
//  Shows preference profile derived from ownership patterns.
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared

/// Owned products list grouped by brand with preference insights.
struct OwnedProductsView: View {
    @Query(sort: \OwnedProduct.acquiredAt, order: .reverse) private var products: [OwnedProduct]
    
    private var groupedByBrand: [(brand: String, products: [OwnedProduct])] {
        let grouped = Dictionary(grouping: products) { $0.brand ?? "Unknown" }
        return grouped.map { (brand: $0.key, products: $0.value) }
            .sorted { $0.products.count > $1.products.count }
    }
    
    var body: some View {
        List {
            // Preference summary
            Section {
                HStack(spacing: 16) {
                    VStack {
                        Text("\(products.count)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Products")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    VStack {
                        Text("\(groupedByBrand.count)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.blue)
                        Text("Brands")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    VStack {
                        Text("\(products.filter { $0.status == .wishlisted }.count)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.pink)
                        Text("Wishlist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } header: {
                Text("Overview")
            }
            
            // Brand groups
            ForEach(groupedByBrand, id: \.brand) { group in
                Section {
                    ForEach(group.products) { product in
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon(product.status))
                                .foregroundStyle(statusColor(product.status))
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.productName)
                                    .font(.subheadline.weight(.medium))
                                
                                if let category = product.category {
                                    Text(category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Text(product.status.rawValue.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusColor(product.status))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(product.status).opacity(0.12), in: Capsule())
                        }
                    }
                } header: {
                    HStack {
                        Text(group.brand)
                        Spacer()
                        Text("\(group.products.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("My Products")
    }
    
    private func statusIcon(_ status: OwnershipStatus) -> String {
        switch status {
        case .owned: return "checkmark.circle.fill"
        case .wishlisted: return "heart.fill"
        case .considering: return "clock.fill"
        case .returned: return "arrow.uturn.left.circle.fill"
        }
    }
    
    private func statusColor(_ status: OwnershipStatus) -> Color {
        switch status {
        case .owned: return .green
        case .wishlisted: return .pink
        case .considering: return .orange
        case .returned: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        OwnedProductsView()
    }
}
