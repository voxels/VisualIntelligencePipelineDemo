//
//  OwnershipButton.swift
//  VisualIntelligencePipeline
//
//  "I Own This" / "I Want This" toggle button for product captures.
//  Supports all OwnershipStatus states (.owned, .wishlisted, .considering, .returned).
//

import SwiftUI
import DiverShared

/// Ownership toggle button that appears on product detail views.
/// Changes icon/label based on current ownership status.
struct OwnershipButton: View {
    let productName: String
    let barcode: String?
    @State private var status: OwnershipStatus = .owned
    @State private var showingPicker = false
    @State private var isOwned = false
    @State private var animateScale = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if isOwned {
                    showingPicker = true
                } else {
                    isOwned = true
                    status = .owned
                    animateScale = true
                }
            }
            
            // Reset scale animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                animateScale = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOwned ? statusIcon : "plus.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: animateScale)
                
                Text(isOwned ? statusLabel : "I Own This")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isOwned ? statusColor.opacity(0.15) : Color.accentColor.opacity(0.1),
                in: Capsule()
            )
            .foregroundStyle(isOwned ? statusColor : .accentColor)
            .overlay(
                Capsule()
                    .strokeBorder(isOwned ? statusColor.opacity(0.3) : Color.accentColor.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(animateScale ? 1.1 : 1.0)
        }
        .confirmationDialog("Ownership Status", isPresented: $showingPicker) {
            Button("I Own This") { status = .owned }
            Button("I Want This") { status = .wishlisted }
            Button("Considering") { status = .considering }
            Button("Returned") { status = .returned }
            Button("Remove", role: .destructive) {
                isOwned = false
            }
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .owned: return "checkmark.circle.fill"
        case .wishlisted: return "heart.fill"
        case .considering: return "clock.fill"
        case .returned: return "arrow.uturn.left.circle.fill"
        }
    }
    
    private var statusLabel: String {
        switch status {
        case .owned: return "I Own This"
        case .wishlisted: return "I Want This"
        case .considering: return "Considering"
        case .returned: return "Returned"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .owned: return .green
        case .wishlisted: return .pink
        case .considering: return .orange
        case .returned: return .gray
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        OwnershipButton(productName: "AirPods Pro", barcode: "190199246850")
        OwnershipButton(productName: "Standing Desk", barcode: nil)
    }
    .padding()
}
