//
//  OwnershipButton.swift
//  DiverUI — cross-platform
//

import SwiftUI
import DiverShared

public struct OwnershipButton: View {
    public let productName: String
    public let barcode: String?
    @State private var status: OwnershipStatus = .owned
    @State private var showingPicker = false
    @State private var isOwned = false
    @State private var animateScale = false

    public init(productName: String, barcode: String?) {
        self.productName = productName
        self.barcode = barcode
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if isOwned { showingPicker = true } else { isOwned = true; status = .owned; animateScale = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { animateScale = false }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOwned ? statusIcon : "plus.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: animateScale)
                Text(isOwned ? statusLabel : "I Own This").font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isOwned ? statusColor.opacity(0.15) : Color.accentColor.opacity(0.1), in: Capsule())
            .foregroundStyle(isOwned ? statusColor : .accentColor)
            .overlay(Capsule().strokeBorder(isOwned ? statusColor.opacity(0.3) : Color.accentColor.opacity(0.2), lineWidth: 1))
            .scaleEffect(animateScale ? 1.1 : 1.0)
        }
        .confirmationDialog("Ownership Status", isPresented: $showingPicker) {
            Button("I Own This") { status = .owned }
            Button("I Want This") { status = .wishlisted }
            Button("Considering") { status = .considering }
            Button("Returned") { status = .returned }
            Button("Remove", role: .destructive) { isOwned = false }
        }
    }

    private var statusIcon: String {
        switch status {
        case .owned: "checkmark.circle.fill"; case .wishlisted: "heart.fill"
        case .considering: "clock.fill"; case .returned: "arrow.uturn.left.circle.fill"
        }
    }
    private var statusLabel: String {
        switch status {
        case .owned: "I Own This"; case .wishlisted: "I Want This"
        case .considering: "Considering"; case .returned: "Returned"
        }
    }
    private var statusColor: Color {
        switch status {
        case .owned: .green; case .wishlisted: .pink; case .considering: .orange; case .returned: .gray
        }
    }
}
