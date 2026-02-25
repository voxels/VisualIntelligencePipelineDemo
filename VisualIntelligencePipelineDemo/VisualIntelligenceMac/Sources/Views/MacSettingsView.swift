//
//  MacSettingsView.swift
//  VisualIntelligenceMac
//
//  Dedicated settings window for macOS with multiple tabs.
//

import SwiftUI
import DiverKit
import DiverShared
import SwiftData

struct MacSettingsView: View {
    @Bindable var installer: EdgeNodeInstallService
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedTab = "edgenode"
    
    // Account / Sync state
    @State private var lastSyncDate: Date? = nil
    @State private var isSyncing = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            
            // ── Edge Node Tab ──
            MacEdgeNodeSettingsTab(installer: installer)
                .tabItem {
                    Label("Edge Node", systemImage: "brain.head.profile")
                }
                .tag("edgenode")
            
            // ── Account & Sync Tab ──
            MacAccountSettingsTab()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag("account")
            
            // ── Maintenance Tab ──
            MacMaintenanceSettingsTab()
                .tabItem {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
                .tag("maintenance")
        }
        .frame(width: 480, height: 360)
        .padding(20)
    }
}

// MARK: - Edge Node Tab

struct MacEdgeNodeSettingsTab: View {
    @Bindable var installer: EdgeNodeInstallService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(installer.isRunning ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                        .frame(width: 60, height: 60)
                    Image(systemName: installer.isRunning ? "brain.filled.head.profile" : "brain.head.profile")
                        .font(.system(size: 30))
                        .foregroundStyle(installer.isRunning ? .green : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Visual Intelligence Edge")
                        .font(.headline)
                    Text(installer.installStatus.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(installer.isRunning ? .green : .secondary)
                }
                Spacer()
            }
            
            Text("The Edge Node allows your iPhone and Vision Pro to offload heavy AI tasks like image analysis and 3D generation to this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Edge Node", isOn: Binding(
                    get: { installer.isRunning },
                    set: { newValue in
                        if newValue { installer.install() }
                        else { installer.uninstall() }
                    }
                ))
                .toggleStyle(.switch)
                
                if installer.installStatus == .requiresApproval {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("System approval required to run as a background service.")
                            .font(.caption)
                        Button("Open Settings") {
                            installer.openSystemSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                
                if let error = installer.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Account Tab

struct MacAccountSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @State private var itemCount: Int = 0

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Library Items", systemImage: "photo.on.rectangle")
                    Spacer()
                    Text("\(itemCount)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Last Cloud Sync", systemImage: "icloud.and.arrow.down")
                    Spacer()
                    Text(syncMonitor.statusDescription)
                        .foregroundStyle(syncMonitor.hasActiveError ? .red : .secondary)
                }
            } header: {
                Text("Library Statistics")
            }
            
            Section {
                Button("Trigger Cloud Sync") {
                    // This triggers a fetch on the main context which usually pokes CloudKit
                    let descriptor = FetchDescriptor<ProcessedItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                    _ = try? modelContext.fetch(descriptor)
                }
            } footer: {
                Text("Data is synchronized automatically via CloudKit. Changes on your iPhone will appear here within moments.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let descriptor = FetchDescriptor<ProcessedItem>()
            itemCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        }
    }
}

// MARK: - Maintenance Tab

struct MacMaintenanceSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isMaintaining = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Library Health")
                    .font(.headline)
                Text("If your sessions or items appear incorrectly, rebuilding the library can fix broken relationships and regenerate missing metadata.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                rebuildLibrary()
            } label: {
                HStack {
                    if isMaintaining {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                        Text("Rebuilding...")
                    } else {
                        Text("Rebuild Library")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMaintaining)
            
            Spacer()
        }
        .padding()
    }
    
    private func rebuildLibrary() {
        isMaintaining = true
        // Simulate background maintenance
        Task {
            try? await Task.sleep(for: .seconds(2))
            isMaintaining = false
        }
    }
}
