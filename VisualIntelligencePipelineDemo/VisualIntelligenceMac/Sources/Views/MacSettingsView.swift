//
//  MacSettingsView.swift
//  VisualIntelligenceMac
//
//  Full settings sheet — 1:1 with the iOS SettingsView, adapted for macOS.
//  Uses NavigationSplitView (sidebar + detail) matching macOS conventions.
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import DiverUI
import AppKit

struct MacSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SidebarViewModel
    @Environment(EdgeNodeInstallService.self) var installer

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general   = "General"
        case commerce  = "Commerce"
        case edgeNode  = "Edge Node"
        case fastVLM   = "On-Device AI"
        case storage   = "Storage"
        case about     = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:  "gear"
            case .commerce: "leaf.fill"
            case .edgeNode: "desktopcomputer"
            case .fastVLM:  "brain.head.profile"
            case .storage:  "externaldrive"
            case .about:    "info.circle"
            }
        }
    }

    @State private var selected: SettingsSection = .general
    @State private var showingClearConfirmation = false
    @State private var isClearing = false
    @State private var showingReprocessing = false
    @State private var fastVLMIsDownloading = false
    @State private var fastVLMDownloadProgress: Double = 0
    @State private var isCLaRaProvisioning = false
    @State private var isMLSharpProvisioning = false
    // Refresh token to re-read file-system model status
    @State private var modelStatusRefreshID = UUID()

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selected) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(160)
        } detail: {
            Group {
                switch selected {
                case .general:   generalView
                case .commerce:  commerceView
                case .edgeNode:  MacEdgeNodeSettingsView(installer: installer)
                case .fastVLM:   fastVLMView
                case .storage:   storageView
                case .about:     aboutView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Delete Database?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteDatabase() }
        } message: {
            Text("This permanently removes all captured items, concepts, and relationships. Cannot be undone.")
        }
        .sheet(isPresented: $showingReprocessing) {
            MacReprocessingView().frame(minWidth: 480, minHeight: 360)
        }
    }

    // MARK: - General

    private var generalView: some View {
        Form {
            Section("Library Maintenance") {
                Button {
                    viewModel.rebuildLibrary(context: modelContext)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Rebuild Library", systemImage: "arrow.triangle.2.circlepath.icloud")
                        if viewModel.isMaintaining {
                            Text(viewModel.maintenanceStatus)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(viewModel.isMaintaining)

                Button { showingReprocessing = true } label: {
                    Label("Reprocess Pipeline…", systemImage: "arrow.triangle.2.circlepath.circle")
                }
            }

            Section("Automation") {
                Label("Shortcuts available via macOS Shortcuts app", systemImage: "wand.and.stars")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    // MARK: - Commerce

    private var commerceView: some View {
        Form {
            Section("Ethical Preferences") {
                NavigationLink { EthicalPolicyConfigView() } label: {
                    Label("Ethical Preferences", systemImage: "leaf.fill").foregroundStyle(.green)
                }
            }
            Section("Owned Products") {
                NavigationLink { OwnedProductsView() } label: {
                    Label("Owned Products", systemImage: "bag.fill").foregroundStyle(.blue)
                }
            }
            Section("API Keys") {
                NavigationLink { APIKeyConfigView() } label: {
                    Label("API Keys", systemImage: "key.fill").foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Commerce Intelligence")
    }

    // MARK: - On-Device AI

    private var fastVLMView: some View {
        Form {
            // FastVLM
            Section {
                Toggle("FastVLM Vision Enrichment", isOn: Binding(
                    get: { FastVLMEnrichmentService.isEnabled },
                    set: { newValue in
                        FastVLMEnrichmentService.setEnabled(newValue)
                        if newValue {
                            if FastVLMEnrichmentService.isModelCached {
                                Services.shared.metadataPipelineService?.fastVLMService = FastVLMEnrichmentService()
                            } else if !fastVLMIsDownloading {
                                fastVLMIsDownloading = true
                                fastVLMDownloadProgress = 0
                                Task {
                                    do {
                                        let svc = FastVLMEnrichmentService()
                                        try await svc.ensureModelAvailable { prog in
                                            Task { @MainActor in fastVLMDownloadProgress = prog }
                                        }
                                        fastVLMIsDownloading = false
                                        Services.shared.metadataPipelineService?.fastVLMService = svc
                                    } catch {
                                        fastVLMIsDownloading = false
                                        FastVLMEnrichmentService.setEnabled(false)
                                    }
                                }
                            }
                        } else {
                            Services.shared.metadataPipelineService?.fastVLMService = nil
                        }
                    }
                ))
                .tint(.purple)
                .disabled(fastVLMIsDownloading)

                if fastVLMIsDownloading {
                    HStack {
                        ProgressView(value: fastVLMDownloadProgress).tint(.purple)
                        Text("\(Int(fastVLMDownloadProgress * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if FastVLMEnrichmentService.isEnabled && FastVLMEnrichmentService.isModelCached {
                    HStack {
                        Label("Model Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Delete") {
                            try? FastVLMEnrichmentService().deleteModel()
                            Services.shared.metadataPipelineService?.fastVLMService = nil
                            FastVLMEnrichmentService.setEnabled(false)
                            modelStatusRefreshID = UUID()
                        }
                        .font(.caption).foregroundStyle(.red)
                    }
                } else {
                    Label("Not downloaded — enable to download", systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Label("FastVLM 1.5B", systemImage: "eye.fill").foregroundStyle(.blue)
            } footer: {
                Text("Vision-language model for on-device image analysis (~3 GB). Runs locally on this Mac via MLX.")
            }

            // CLaRa
            Section {
                ModelStatusRow(
                    id: "clara",
                    readyPath: claraReadyPath,
                    isProvisioning: isCLaRaProvisioning,
                    refreshID: modelStatusRefreshID
                )
                HStack {
                    if isCLaRaProvisioning {
                        ProgressView().controlSize(.small)
                        Text("Provisioning via Edge Node…")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Provision via Edge Node") {
                            isCLaRaProvisioning = true
                            Task.detached(priority: .utility) {
                                await EdgeModelProvisioner.shared.downloadCLaRa()
                                await MainActor.run {
                                    isCLaRaProvisioning = false
                                    modelStatusRefreshID = UUID()
                                }
                            }
                        }
                        .disabled(isCLaRaProvisioning)

                        Spacer()

                        if FileManager.default.fileExists(atPath: claraReadyPath) {
                            Button("Delete") {
                                let dir = (claraReadyPath as NSString).deletingLastPathComponent
                                try? FileManager.default.removeItem(atPath: dir)
                                modelStatusRefreshID = UUID()
                            }
                            .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            } header: {
                Label("CLaRa 7B", systemImage: "brain.head.profile").foregroundStyle(.purple)
            } footer: {
                Text("Qwen2-7B + LoRA adapter for context-aware summarization and agentic chat (~14 GB). Provisioned by the Edge Node — requires Python 3 and ~20 min on first run.")
            }

            // ML-Sharp
            Section {
                ModelStatusRow(
                    id: "mlsharp",
                    readyPath: mlSharpReadyPath,
                    isProvisioning: isMLSharpProvisioning,
                    refreshID: modelStatusRefreshID
                )
                HStack {
                    if isMLSharpProvisioning {
                        ProgressView().controlSize(.small)
                        Text("Provisioning via Edge Node…")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Provision via Edge Node") {
                            isMLSharpProvisioning = true
                            Task.detached(priority: .utility) {
                                await EdgeModelProvisioner.shared.downloadMLSharp()
                                await MainActor.run {
                                    isMLSharpProvisioning = false
                                    modelStatusRefreshID = UUID()
                                }
                            }
                        }
                        .disabled(isMLSharpProvisioning)

                        Spacer()

                        if FileManager.default.fileExists(atPath: mlSharpReadyPath) {
                            Button("Delete") {
                                let dir = (mlSharpReadyPath as NSString).deletingLastPathComponent
                                try? FileManager.default.removeItem(atPath: dir)
                                modelStatusRefreshID = UUID()
                            }
                            .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            } header: {
                Label("ML-Sharp 3D Engine", systemImage: "rotate.3d").foregroundStyle(.orange)
            } footer: {
                Text("Apple's semantic edge model for 3D Gaussian Splat generation (~500 MB). Provisioned by the Edge Node via git + Python venv.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("On-Device AI")
        .id(modelStatusRefreshID)
    }

    // Paths visible to the EdgeDaemon (unsandboxed). The sandboxed Mac app can read
    // these via FileManager even though it can't write there — sandbox allows reads
    // of files not in its own container when using fully-qualified paths.
    private var claraReadyPath: String {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Models/CLaRa")
        return base.appendingPathComponent("model.safetensors.index.json").path
    }
    private var mlSharpReadyPath: String {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Models/ml-sharp")
        return base.appendingPathComponent("enhance.py").path
    }

    // MARK: - Storage

    private var storageView: some View {
        Form {
            Section {
                MacStorageInfoRow()
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    if isClearing {
                        HStack { Text("Deleting…"); Spacer(); ProgressView().controlSize(.small) }
                    } else {
                        Label("Delete Database", systemImage: "trash")
                    }
                }
                .disabled(isClearing)
            } header: {
                Text("Storage")
            } footer: {
                Text("Permanently deletes all items, references, concepts, and relationships.")
            }

            Section("Logs") {
                Button { exportLogs() } label: {
                    Label("Export Processing Logs", systemImage: "square.and.arrow.up")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
    }

    // MARK: - About

    private var aboutView: some View {
        Form {
            Section("About") {
                LabeledContent("Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                LabeledContent("Build",
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }

    // MARK: - Helpers

    private func deleteDatabase() {
        isClearing = true
        Task {
            do {
                // Delete all SwiftData models available in the Mac target
                try modelContext.delete(model: ProcessedItem.self)
                try modelContext.delete(model: SessionMetadata.self)
                try modelContext.delete(model: LocalInput.self)
                try modelContext.delete(model: SessionCollection.self)
                try modelContext.delete(model: UserConcept.self)
                try modelContext.save()
                await MainActor.run { isClearing = false }
            } catch {
                await MainActor.run { isClearing = false }
            }
        }
    }

    private func exportLogs() {
        Task {
            guard let items = try? modelContext.fetch(
                FetchDescriptor<ProcessedItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            ) else { return }

            struct LogEntry: Encodable {
                let id: String; let title: String?; let createdAt: Date; let logs: [String]
            }
            let entries = items.map { LogEntry(id: $0.id, title: $0.title, createdAt: $0.createdAt, logs: $0.processingLog) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(entries) else { return }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vi_logs_\(Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")).json")
            try? data.write(to: url)
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

private struct MacStorageInfoRow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var count = 0
    var body: some View {
        LabeledContent("Processed Items", value: "\(count)")
            .onAppear {
                count = (try? modelContext.fetchCount(FetchDescriptor<ProcessedItem>())) ?? 0
            }
    }
}

// MARK: - Mac Edge Node Settings

/// Mac-native edge node panel. On macOS you ARE the edge node —
/// this shows LoginItem install status and how to connect iPhones to this Mac.
private struct MacEdgeNodeSettingsView: View {
    @Bindable var installer: EdgeNodeInstallService

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: statusIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(statusColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Visual Intelligence Node")
                            .font(.headline)
                        Text(installer.installStatus.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if let error = installer.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Node Status")
            } footer: {
                Text("This Mac can act as an Edge Node for Visual Intelligence on iPhone. The node runs as a background login item and is accessible over your local network via TLS 1.3.")
            }

            Section("Actions") {
                if installer.installStatus == .running {
                    Button("Disable Edge Node", role: .destructive) {
                        installer.uninstall()
                    }
                } else if installer.installStatus == .requiresApproval {
                    Button("Open System Settings…") {
                        installer.openSystemSettings()
                    }
                    Label("macOS requires your approval in System Settings → General → Login Items", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Enable Edge Node") {
                        installer.install()
                    }
                    .disabled(installer.installStatus == .installing)
                    .buttonStyle(.borderedProminent)
                }

                Button("Refresh Status") {
                    installer.refresh()
                }
                .foregroundStyle(.secondary)
            }

            Section("Connecting iPhones") {
                EdgeFeatureBullet(
                    icon: "wifi", color: .blue,
                    title: "Same Wi-Fi Required",
                    body: "Your iPhone and this Mac must be on the same local network. Hotspot works too."
                )
                EdgeFeatureBullet(
                    icon: "iphone", color: .purple,
                    title: "Automatic Discovery",
                    body: "Open Visual Intelligence on iPhone → Settings → Edge Node. This Mac will appear automatically via Bonjour."
                )
                EdgeFeatureBullet(
                    icon: "lock.shield.fill", color: .green,
                    title: "Encrypted",
                    body: "All traffic uses TLS 1.3. Nothing leaves your local network."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Edge Node")
    }

    private var statusColor: Color {
        switch installer.installStatus {
        case .running:          .green
        case .installing:       .blue
        case .requiresApproval: .orange
        case .error:            .red
        case .notInstalled:     .secondary
        }
    }

    private var statusIcon: String {
        switch installer.installStatus {
        case .running:          "checkmark.circle.fill"
        case .installing:       "arrow.down.circle"
        case .requiresApproval: "hand.raised.fill"
        case .error:            "exclamationmark.triangle.fill"
        case .notInstalled:     "desktopcomputer.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - Model Status Row

private struct ModelStatusRow: View {
    let id: String
    let readyPath: String
    let isProvisioning: Bool
    let refreshID: UUID

    private var isReady: Bool {
        FileManager.default.fileExists(atPath: readyPath)
    }

    var body: some View {
        HStack {
            if isProvisioning {
                Label("Provisioning…", systemImage: "arrow.down.circle")
                    .foregroundStyle(.blue)
            } else if isReady {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not installed", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .id(refreshID)
    }
}

