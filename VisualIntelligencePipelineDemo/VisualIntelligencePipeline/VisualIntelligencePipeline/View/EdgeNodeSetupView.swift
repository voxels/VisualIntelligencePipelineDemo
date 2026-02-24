//
//  EdgeNodeSetupView.swift
//  VisualIntelligencePipeline
//
//  "Get Edge Node" settings screen. Shows connected node info when found,
//  or a guided setup flow when no node is detected on the local Wi-Fi.
//
//  Distribution approaches (in order of preference):
//    1. Universal Purchase — Mac App Store companion app (same Apple ID)
//    2. TestFlight — beta distribution alongside iOS build
//    3. Direct download — notarized .dmg from project website
//

import SwiftUI
import DiverKit

// MARK: - EdgeNodeSetupView

struct EdgeNodeSetupView: View {

    // MARK: State

    @State private var connectedNode: EdgeNodeInfo?
    @State private var availableNodes: [EdgeNodeInfo] = []
    @State private var isScanning = false
    @State private var scanPulse = false
    @State private var showDownloadSheet = false

    // MARK: Body

    var body: some View {
        List {
            if let node = connectedNode {
                connectedSection(node: node)
            } else {
                notConnectedSection
            }

            if !availableNodes.isEmpty && connectedNode == nil {
                availableNodesSection
            }

            howItWorksSection
        }
        .navigationTitle("Edge Node")
        .navigationBarTitleDisplayMode(.large)
        .task { await refresh() }
        .sheet(isPresented: $showDownloadSheet) {
            DownloadEdgeNodeSheet()
        }
    }

    // MARK: Connected

    @ViewBuilder
    private func connectedSection(node: EdgeNodeInfo) -> some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.deviceName)
                        .font(.headline)
                    Text(node.chipFamily)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Label("\(node.physicalMemoryGB) GB", systemImage: "memorychip")
                        if node.neuralEngineTOPS > 0 {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Label(String(format: "%.0f TOPS", node.neuralEngineTOPS),
                                  systemImage: "bolt.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Connected")
        } footer: {
            Text("Heavy ML inference — CLaRa 7B, FastVLM 1.5B, and 3D scene generation — is automatically offloaded to this Mac over your local network.")
        }

        if !node.availableModels.isEmpty {
            Section("Available Models") {
                ForEach(node.availableModels, id: \.self) { model in
                    Label(model, systemImage: modelIcon(for: model))
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: Not Connected

    private var notConnectedSection: some View {
        Section {
            VStack(spacing: 20) {
                // Pulse animation
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(.blue.opacity(scanPulse ? 0 : 0.3 - Double(i) * 0.08), lineWidth: 1.5)
                            .frame(width: CGFloat(56 + i * 22), height: CGFloat(56 + i * 22))
                            .scaleEffect(scanPulse ? 1.6 : 1)
                            .animation(
                                .easeOut(duration: 1.4)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.4),
                                value: scanPulse
                            )
                    }
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                        .frame(width: 56, height: 56)
                        .background(.blue.opacity(0.12), in: Circle())
                }
                .padding(.top, 8)
                .onAppear { scanPulse = true }

                VStack(spacing: 6) {
                    Text("No Edge Node Found")
                        .font(.headline)
                    Text("Make sure your Mac is on the same Wi-Fi network and the Visual Intelligence Edge Node app is running.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label(isScanning ? "Searching…" : "Search Again",
                              systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanning)

                    Button {
                        showDownloadSheet = true
                    } label: {
                        Label("Get for Mac", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            Text("Edge Node Status")
        }
    }

    // MARK: Available Nodes (discovered but not connected)

    private var availableNodesSection: some View {
        Section("Nearby Macs") {
            ForEach(availableNodes, id: \.deviceName) { node in
                Button {
                    Task {
                        try? await Services.shared.discoveryService?.connect(to: node)
                        await refresh()
                    }
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.deviceName)
                                .foregroundStyle(.primary)
                            Text(node.chipFamily + " · \(node.physicalMemoryGB) GB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: How It Works

    private var howItWorksSection: some View {
        Section("How It Works") {
            FeatureBullet(
                icon: "lock.shield.fill",
                color: .green,
                title: "Encrypted Local Network",
                descriptionText: "All traffic between your iPhone and Mac uses TLS 1.3. Nothing leaves your home network."
            )
            FeatureBullet(
                icon: "iphone.and.arrow.right.inward",
                color: .blue,
                title: "Automatic Fallback",
                descriptionText: "If no Mac is found, all AI runs on-device. Edge offloading is always optional and transparent."
            )
            FeatureBullet(
                icon: "cpu.fill",
                color: .purple,
                title: "Larger Models",
                descriptionText: "The Mac node runs CLaRa 7B and FastVLM 1.5B for richer summaries and higher-fidelity image understanding than the on-device models."
            )
            FeatureBullet(
                icon: "wand.and.stars",
                color: .orange,
                title: "3D Scene Generation",
                descriptionText: "With an M-series Mac node, any capture can be converted into a 3D Gaussian Splat viewable in AR."
            )
        }
    }

    // MARK: Helpers

    private func refresh() async {
        isScanning = true
        defer { isScanning = false }
        guard let discovery = Services.shared.discoveryService else { return }
        connectedNode = await discovery.connectedNode
        availableNodes = await discovery.availableNodes.filter { $0.isAvailable }
        // If we have exactly one node and none connected, auto-connect
        if connectedNode == nil, availableNodes.count == 1 {
            try? await discovery.connect(to: availableNodes[0])
            connectedNode = await discovery.connectedNode
        }
    }

    private func modelIcon(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("clara") { return "brain.head.profile" }
        if lower.contains("fastvlm") { return "eye" }
        if lower.contains("ml-sharp") || lower.contains("splat") { return "rotate.3d" }
        if lower.contains("yolo") || lower.contains("vision") { return "viewfinder" }
        return "cpu"
    }
}

// MARK: - FeatureBullet

private struct FeatureBullet: View {
    let icon: String
    let color: Color
    let title: String
    let descriptionText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DownloadEdgeNodeSheet

private struct DownloadEdgeNodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "desktopcomputer.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                            .padding(.top, 8)

                        Text("Get the Edge Node")
                            .font(.title2.bold())

                        Text("Install the Visual Intelligence Edge Node companion app on your Mac to unlock larger AI models and 3D scene generation.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Section("Install Options") {
                    // Option 1: Mac App Store (primary)
                    Link(destination: URL(string: "macappstore://")!) {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mac App Store")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Recommended — included with your purchase")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "apple.logo")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Option 2: TestFlight (beta)
                    Link(destination: URL(string: "https://testflight.apple.com")!) {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TestFlight (Beta)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("For beta testers — open on your Mac")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "app.badge.checkmark")
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Setup Steps") {
                    ForEach(setupSteps, id: \.number) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(step.number)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(.blue, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(step.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Edge Node Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private struct SetupStep {
        let number: Int
        let title: String
        let detail: String
    }

    private let setupSteps = [
        SetupStep(number: 1, title: "Download on your Mac",
                  detail: "Install Visual Intelligence Edge Node from the Mac App Store on any M-series Mac."),
        SetupStep(number: 2, title: "Connect to the same Wi-Fi",
                  detail: "Your iPhone and Mac must be on the same local Wi-Fi network."),
        SetupStep(number: 3, title: "Open the Edge Node app",
                  detail: "It runs as a menu bar app — look for the ⌁ icon in your Mac's menu bar."),
        SetupStep(number: 4, title: "Return here and tap Search",
                  detail: "Your Mac will appear automatically. No pairing or configuration needed."),
    ]
}

// MARK: - EdgeNodeStatusPill
// Inline badge for the Settings row — polls discovery service every 5s.

struct EdgeNodeStatusPill: View {
    @State private var isConnected = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(isConnected ? "Connected" : "Not Found")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isConnected ? .green : .secondary)
        }
        .task {
            while !Task.isCancelled {
                if let discovery = Services.shared.discoveryService {
                    isConnected = await discovery.isEdgeNodeConnected
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EdgeNodeSetupView()
    }
}
