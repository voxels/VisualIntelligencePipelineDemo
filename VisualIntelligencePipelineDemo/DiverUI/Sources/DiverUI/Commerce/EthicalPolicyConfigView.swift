//
//  EthicalPolicyConfigView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared

/// Ethical policy preferences for commerce routing.
/// Settings are persisted via SwiftData and synced across devices via CloudKit.
public struct EthicalPolicyConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [EthicalPolicySettings]

    public init() {}

    private var settings: EthicalPolicySettings {
        allSettings.first ?? EthicalPolicySettings.current(in: modelContext)
    }

    private let availableCertifications = [
        "B Corp", "Fair Trade", "Organic", "Carbon Neutral",
        "Rainforest Alliance", "USDA Organic", "1% for the Planet"
    ]

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "leaf.fill").foregroundStyle(.green)
                        Text("Carbon Footprint Threshold").font(.subheadline.weight(.semibold))
                    }
                    Slider(value: Binding(
                        get: { settings.carbonThreshold },
                        set: { settings.carbonThreshold = $0; save() }
                    ), in: 0...1, step: 0.1).tint(carbonColor)
                    HStack {
                        Text("Strictest").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(carbonLabel).font(.caption.weight(.semibold)).foregroundStyle(carbonColor)
                        Spacer()
                        Text("No Filter").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Environmental") }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.excludeLaborViolations },
                    set: { settings.excludeLaborViolations = $0; save() }
                )) {
                    Label("Exclude Labor Violations", systemImage: "person.badge.shield.checkmark.fill")
                }.tint(.orange)
            } header: { Text("Social") } footer: {
                Text("Hide platforms with documented labor practice violations from purchase recommendations.")
            }

            Section {
                ForEach(availableCertifications, id: \.self) { cert in
                    HStack {
                        Text(cert); Spacer()
                        if settings.certifications.contains(cert) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            if settings.certifications.contains(cert) {
                                settings.certifications.removeAll { $0 == cert }
                            } else {
                                settings.certifications.append(cert)
                            }
                            save()
                        }
                    }
                }
            } header: { Text("Preferred Certifications") } footer: {
                Text("Platforms matching your certifications rank higher in recommendations.")
            }

            Section {
                ForEach(settings.platformRanking, id: \.self) { platform in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Text(displayName(platform))
                    }
                }
                .onMove { from, to in settings.platformRanking.move(fromOffsets: from, toOffset: to); save() }
            } header: { Text("Platform Preference Order") } footer: {
                Text("Drag to reorder. Top platforms get priority in recommendations.")
            }
        }
        .navigationTitle("Ethical Policy")
    }

    private func save() {
        settings.updatedAt = Date()
        try? modelContext.save()
    }

    private var carbonColor: Color {
        settings.carbonThreshold <= 0.3 ? .green : settings.carbonThreshold <= 0.6 ? .orange : .red
    }

    private var carbonLabel: String {
        if settings.carbonThreshold <= 0.2 { return "Very Strict" }
        if settings.carbonThreshold <= 0.4 { return "Strict" }
        if settings.carbonThreshold <= 0.6 { return "Moderate" }
        if settings.carbonThreshold <= 0.8 { return "Relaxed" }
        return "No Filter"
    }

    private func displayName(_ platform: String) -> String {
        switch platform {
        case "amazon": "Amazon"; case "target": "Target"; case "bestbuy": "Best Buy"
        case "ebay": "eBay"; case "thrive_market": "Thrive Market"; default: platform.capitalized
        }
    }
}
