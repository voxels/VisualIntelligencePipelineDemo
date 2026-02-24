//
//  APIKeyConfigView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import DiverKit

public struct APIKeyConfigView: View {
    @State private var keyValues: [APIKeyService.APIKey: String] = [:]
    @State private var keyStatus: [APIKeyService.APIKey: Bool] = [:]
    @State private var showingSaveConfirmation = false
    @State private var isSaving = false

    private let apiKeyService = APIKeyService()

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(APIKeyService.APIKey.allCases, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: iconForKey(key)).foregroundStyle(colorForKey(key))
                            Text(labelForKey(key)).font(.subheadline.weight(.semibold))
                            Spacer()
                            if keyStatus[key] == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            }
                        }
                        SecureField("API Key", text: Binding(
                            get: { keyValues[key] ?? "" }, set: { keyValues[key] = $0 }
                        ))
                        .textContentType(.password)
                        .font(.system(.caption, design: .monospaced))
                        Text(descriptionForKey(key)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("API Keys") } footer: {
                Text("Keys are stored in iCloud via the Keys CloudKit container. They sync across your devices automatically.")
            }

            Section {
                Button { saveAllKeys() } label: {
                    if isSaving { ProgressView() } else { Label("Save All Keys", systemImage: "key.fill") }
                }
                .disabled(keyValues.values.allSatisfy { $0.isEmpty } || isSaving)

                Button(role: .destructive) { deleteAllKeys() } label: {
                    Label("Delete All Keys", systemImage: "trash")
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("API Keys")
        .task { await refreshStatus() }
        .alert("Keys Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("API keys have been saved to iCloud and will sync across your devices.")
        }
    }

    private func saveAllKeys() {
        isSaving = true
        Task {
            for (key, value) in keyValues where !value.isEmpty { try? await apiKeyService.store(key: value, for: key) }
            await refreshStatus(); isSaving = false; showingSaveConfirmation = true
        }
    }

    private func deleteAllKeys() {
        Task {
            for key in APIKeyService.APIKey.allCases { try? await apiKeyService.delete(for: key) }
            keyValues = [:]; await refreshStatus()
        }
    }

    private func refreshStatus() async {
        await apiKeyService.prefetchKeys(); keyStatus = apiKeyService.configurationStatus()
    }

    private func iconForKey(_ key: APIKeyService.APIKey) -> String {
        switch key {
        case .reddit: "text.bubble.fill"; case .ifixit: "wrench.and.screwdriver.fill"
        case .amazonAssociates: "cart.fill"; case .ebayPartnerNetwork: "tag.fill"; case .targetPartners: "target"
        case .bestBuyAffiliate: "desktopcomputer"; case .thriveMarketReferral: "leaf.fill"
        }
    }

    private func colorForKey(_ key: APIKeyService.APIKey) -> Color {
        switch key {
        case .reddit: .orange; case .ifixit: .green; case .amazonAssociates: .yellow
        case .ebayPartnerNetwork: .red; case .targetPartners: .red; case .bestBuyAffiliate: .blue; case .thriveMarketReferral: .green
        }
    }

    private func labelForKey(_ key: APIKeyService.APIKey) -> String {
        switch key {
        case .reddit: "Reddit"; case .ifixit: "iFixit"
        case .amazonAssociates: "Amazon Associates"; case .ebayPartnerNetwork: "eBay Partner Network"
        case .targetPartners: "Target Affiliate"; case .bestBuyAffiliate: "Best Buy Affiliate"
        case .thriveMarketReferral: "Thrive Market Referral"
        }
    }

    private func descriptionForKey(_ key: APIKeyService.APIKey) -> String {
        switch key {
        case .reddit: "Used for community sentiment analysis in Social Proof scoring."
        case .ifixit: "Used for repair guide lookup in Community Repairability scoring."
        case .amazonAssociates: "Your Amazon Associates tag (e.g. mysite-20). Sign up at affiliate-program.amazon.com"
        case .ebayPartnerNetwork: "Your eBay Partner Network Campaign ID. Sign up at partnernetwork.ebay.com"
        case .targetPartners: "Your Target affiliate ID from Impact Radius. Apply at partners.target.com"
        case .bestBuyAffiliate: "Your Best Buy click ID from Impact Radius. Apply at partners.bestbuy.com"
        case .thriveMarketReferral: "Your Thrive Market referral code. Found in your account settings."
        }
    }
}
