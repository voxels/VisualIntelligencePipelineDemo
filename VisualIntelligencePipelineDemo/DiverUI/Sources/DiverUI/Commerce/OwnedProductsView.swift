//
//  OwnedProductsView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared

public struct OwnedProductsView: View {
    @Query(sort: \OwnedProduct.acquiredAt, order: .reverse) private var products: [OwnedProduct]
    public init() {}

    private var groupedByBrand: [(brand: String, products: [OwnedProduct])] {
        Dictionary(grouping: products) { $0.brand ?? "Unknown" }
            .map { (brand: $0.key, products: $0.value) }
            .sorted { $0.products.count > $1.products.count }
    }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    statCell(value: products.count, label: "Products", color: .primary)
                    Divider()
                    statCell(value: groupedByBrand.count, label: "Brands", color: .blue)
                    Divider()
                    statCell(value: products.filter { $0.status == .wishlisted }.count, label: "Wishlist", color: .pink)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            } header: { Text("Overview") }

            ForEach(groupedByBrand, id: \.brand) { group in
                Section {
                    ForEach(group.products) { product in
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon(product.status))
                                .foregroundStyle(statusColor(product.status)).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.productName).font(.subheadline.weight(.medium))
                                if let cat = product.category {
                                    Text(cat).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(product.status.rawValue.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusColor(product.status))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(statusColor(product.status).opacity(0.12), in: Capsule())
                        }
                    }
                } header: {
                    HStack {
                        Text(group.brand); Spacer()
                        Text("\(group.products.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("My Products")
    }

    @ViewBuilder private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func statusIcon(_ s: OwnershipStatus) -> String {
        switch s {
        case .owned: "checkmark.circle.fill"; case .wishlisted: "heart.fill"
        case .considering: "clock.fill"; case .returned: "arrow.uturn.left.circle.fill"
        }
    }
    private func statusColor(_ s: OwnershipStatus) -> Color {
        switch s {
        case .owned: .green; case .wishlisted: .pink; case .considering: .orange; case .returned: .gray
        }
    }
}
