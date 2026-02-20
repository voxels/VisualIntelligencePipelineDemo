//
//  EthicalPolicyConfigView.swift
//  VisualIntelligencePipeline
//
//  Settings view for configuring the user's ethical purchasing preferences.
//  Controls carbon threshold, certifications, platform ranking, and labor filtering.
//

import SwiftUI
import DiverShared

/// Ethical policy configuration for commerce routing.
struct EthicalPolicyConfigView: View {
    @State private var carbonThreshold: Float = 0.5
    @State private var excludeLaborViolations = false
    @State private var certifications: [String] = []
    @State private var platformRanking: [String] = ["thrive_market", "target", "bestbuy", "ebay", "amazon"]
    
    private let availableCertifications = [
        "B Corp", "Fair Trade", "Organic", "Carbon Neutral",
        "Rainforest Alliance", "USDA Organic", "1% for the Planet"
    ]
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(.green)
                        Text("Carbon Footprint Threshold")
                            .font(.subheadline.weight(.semibold))
                    }
                    
                    Slider(value: $carbonThreshold, in: 0...1, step: 0.1)
                        .tint(carbonColor)
                    
                    HStack {
                        Text("Strictest")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(carbonLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(carbonColor)
                        Spacer()
                        Text("No Filter")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Environmental")
            }
            
            Section {
                Toggle(isOn: $excludeLaborViolations) {
                    Label("Exclude Labor Violations", systemImage: "person.badge.shield.checkmark.fill")
                }
                .tint(.orange)
            } header: {
                Text("Social")
            } footer: {
                Text("Hide platforms with documented labor practice violations from purchase recommendations.")
            }
            
            Section {
                ForEach(availableCertifications, id: \.self) { cert in
                    HStack {
                        Text(cert)
                        Spacer()
                        if certifications.contains(cert) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            if certifications.contains(cert) {
                                certifications.removeAll { $0 == cert }
                            } else {
                                certifications.append(cert)
                            }
                        }
                    }
                }
            } header: {
                Text("Preferred Certifications")
            } footer: {
                Text("Platforms matching your certifications rank higher in recommendations.")
            }
            
            Section {
                ForEach(platformRanking, id: \.self) { platform in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(displayName(platform))
                    }
                }
                .onMove { from, to in
                    platformRanking.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("Platform Preference Order")
            } footer: {
                Text("Drag to reorder. Top platforms get priority in recommendations.")
            }
        }
        .navigationTitle("Ethical Policy")
    }
    
    private var carbonColor: Color {
        if carbonThreshold <= 0.3 { return .green }
        if carbonThreshold <= 0.6 { return .orange }
        return .red
    }
    
    private var carbonLabel: String {
        if carbonThreshold <= 0.2 { return "Very Strict" }
        if carbonThreshold <= 0.4 { return "Strict" }
        if carbonThreshold <= 0.6 { return "Moderate" }
        if carbonThreshold <= 0.8 { return "Relaxed" }
        return "No Filter"
    }
    
    private func displayName(_ platform: String) -> String {
        switch platform {
        case "amazon": return "Amazon"
        case "target": return "Target"
        case "bestbuy": return "Best Buy"
        case "ebay": return "eBay"
        case "thrive_market": return "Thrive Market"
        default: return platform.capitalized
        }
    }
}

#Preview {
    NavigationStack {
        EthicalPolicyConfigView()
    }
}
