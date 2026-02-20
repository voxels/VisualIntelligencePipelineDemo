//
//  APIKeyConfigView.swift
//  VisualIntelligencePipeline
//
//  Settings view for managing API keys stored in CloudKit.
//  Supports Foursquare, Reddit, and iFixit API keys.
//

import SwiftUI
import DiverKit

/// API key configuration view for third-party service keys.
struct APIKeyConfigView: View {
    @State private var keyValues: [APIKeyService.APIKey: String] = [:]
    @State private var keyStatus: [APIKeyService.APIKey: Bool] = [:]
    @State private var showingSaveConfirmation = false
    @State private var isSaving = false
    
    private let apiKeyService = APIKeyService()
    
    var body: some View {
        Form {
            Section {
                ForEach(APIKeyService.APIKey.allCases, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: iconForKey(key))
                                .foregroundStyle(colorForKey(key))
                            Text(labelForKey(key))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if keyStatus[key] == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        
                        SecureField("API Key", text: Binding(
                            get: { keyValues[key] ?? "" },
                            set: { keyValues[key] = $0 }
                        ))
                        .textContentType(.password)
                        .font(.system(.caption, design: .monospaced))
                        
                        Text(descriptionForKey(key))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("API Keys")
            } footer: {
                Text("Keys are stored in iCloud via the Keys CloudKit container. They sync across your devices automatically.")
            }
            
            Section {
                Button {
                    saveAllKeys()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Save All Keys", systemImage: "key.fill")
                    }
                }
                .disabled(keyValues.values.allSatisfy { $0.isEmpty } || isSaving)
                
                Button(role: .destructive) {
                    deleteAllKeys()
                } label: {
                    Label("Delete All Keys", systemImage: "trash")
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("API Keys")
        .task {
            await refreshStatus()
        }
        .alert("Keys Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("API keys have been saved to iCloud and will sync across your devices.")
        }
    }
    
    private func saveAllKeys() {
        isSaving = true
        Task {
            for (key, value) in keyValues where !value.isEmpty {
                try? await apiKeyService.store(key: value, for: key)
            }
            await refreshStatus()
            isSaving = false
            showingSaveConfirmation = true
        }
    }
    
    private func deleteAllKeys() {
        Task {
            for key in APIKeyService.APIKey.allCases {
                try? await apiKeyService.delete(for: key)
            }
            keyValues = [:]
            await refreshStatus()
        }
    }
    
    private func refreshStatus() async {
        await apiKeyService.prefetchKeys()
        keyStatus = apiKeyService.configurationStatus()
    }
    
    private func iconForKey(_ key: APIKeyService.APIKey) -> String {
        switch key {
        case .foursquare: return "map.fill"
        case .reddit: return "text.bubble.fill"
        case .ifixit: return "wrench.and.screwdriver.fill"
        }
    }
    
    private func colorForKey(_ key: APIKeyService.APIKey) -> Color {
        switch key {
        case .foursquare: return .blue
        case .reddit: return .orange
        case .ifixit: return .green
        }
    }
    
    private func labelForKey(_ key: APIKeyService.APIKey) -> String {
        switch key {
        case .foursquare: return "Foursquare"
        case .reddit: return "Reddit"
        case .ifixit: return "iFixit"
        }
    }
    
    private func descriptionForKey(_ key: APIKeyService.APIKey) -> String {
        switch key {
        case .foursquare: return "Used for venue-level location search in the editing UI."
        case .reddit: return "Used for community sentiment analysis in Social Proof scoring."
        case .ifixit: return "Used for repair guide lookup in Community Repairability scoring."
        }
    }
}

#Preview {
    NavigationStack {
        APIKeyConfigView()
    }
}
