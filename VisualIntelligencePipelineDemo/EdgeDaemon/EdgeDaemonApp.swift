//
//  EdgeDaemonApp.swift
//  EdgeDaemon
//
//  SwiftUI menu bar app that serves as an ML edge node for the
//  Visual Intelligence pipeline. Replaces the CLI entry point.
//

import SwiftUI
import DiverKit
import ServiceManagement

@main
struct EdgeDaemonApp: App {
    @State private var service = EdgeDaemonService()
    @State private var isLoginItemEnabled = SMAppService.loginItem(identifier: "com.secretatomics.visualintelligence.mac.edgenode.helper").status == .enabled

    var body: some Scene {
        MenuBarExtra {
            EdgeDaemonMenu(
                service: service,
                isLoginItemEnabled: $isLoginItemEnabled
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: service.isListening
                      ? "brain.filled.head.profile"
                      : "brain.head.profile")
                if service.status == .processing {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                }
            }
        }
        .menuBarExtraStyle(.window)  // enables custom SwiftUI panel instead of plain menu
    }
}

// MARK: - Menu Content

struct EdgeDaemonMenu: View {
    @Bindable var service: EdgeDaemonService
    @Binding var isLoginItemEnabled: Bool

    @State private var uptimeTimer: Timer?
    @State private var uptimeSeconds: Int = 0
    @State private var startDate: Date = Date()
    @State private var recentActivity: [ActivityEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header bar ──
            headerBar
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Stats row ──
                    statsRow
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    sectionDivider("Models")

                    // ── Model list ──
                    modelsSection
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)

                    sectionDivider("Connected Devices")

                    // ── Clients ──
                    clientsSection
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)

                    if !recentActivity.isEmpty {
                        sectionDivider("Recent Activity")
                        activitySection
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxHeight: 340)

            Divider().opacity(0.5)

            // ── Controls ──
            controlsSection
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .task {
            // Start uptime tracking when listening begins
            startDate = Date()
            uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                uptimeSeconds = Int(Date().timeIntervalSince(startDate))
            }
        }
        .onDisappear {
            uptimeTimer?.invalidate()
        }
        .onChange(of: service.totalRequests) { _, count in
            if let last = recentActivity.last, last.label == service.status.rawValue { return }
            recentActivity.insert(
                ActivityEntry(time: Date(), label: "\(service.status.rawValue) — req #\(count)"),
                at: 0
            )
            if recentActivity.count > 8 { recentActivity.removeLast() }
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: service.isListening
                      ? "brain.filled.head.profile"
                      : "brain.head.profile")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Visual Intelligence Edge")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Uptime pill (only when listening)
            if service.isListening {
                Text(formattedUptime)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
        }
    }

    // MARK: Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(service.totalRequests)", label: "Requests", icon: "bolt")
            Divider().frame(height: 28)
            statCell(value: "\(service.connectedClients.count)", label: "Clients", icon: "iphone")
            Divider().frame(height: 28)
            statCell(value: "\(service.loadedModels.count)", label: "Models", icon: "cpu")
            Divider().frame(height: 28)
            statCell(value: "8847", label: "Port", icon: "network")
        }
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: Models Section

    private var modelsSection: some View {
        VStack(spacing: 4) {
            if service.loadedModels.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("No models loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(service.loadedModels, id: \.self) { model in
                    modelRow(model)
                }
            }
        }
    }

    private func modelRow(_ model: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: modelIcon(for: model))
                .font(.system(size: 11))
                .foregroundStyle(modelColor(for: model))
                .frame(width: 18)
            Text(model)
                .font(.system(size: 12))
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }

    // MARK: Clients Section

    private var clientsSection: some View {
        VStack(spacing: 4) {
            if service.connectedClients.isEmpty {
                HStack {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("No iOS clients connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(service.connectedClients, id: \.self) { client in
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                            .frame(width: 18)
                        Text(client)
                            .font(.system(size: 12))
                        Spacer()
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: Activity Section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(recentActivity) { entry in
                HStack(spacing: 6) {
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 56, alignment: .leading)
                    Text(entry.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Controls

    private var controlsSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if service.isListening {
                    Button {
                        service.stopListening()
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        service.startListening()
                        startDate = Date()
                        uptimeSeconds = 0
                    } label: {
                        Label("Start", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Toggle("", isOn: $isLoginItemEnabled)
                    .toggleStyle(.checkbox)
                    .help("Start at Login")
                    .onChange(of: isLoginItemEnabled) { _, enabled in
                        toggleLoginItem(enabled: enabled)
                    }
                Text("Login")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                service.stopListening()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Visual Intelligence Edge", systemImage: "power")
                    .frame(maxWidth: .infinity)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
    }

    // MARK: Helpers

    private func sectionDivider(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var statusColor: Color {
        switch service.status {
        case .listening:   .green
        case .processing:  .blue
        case .error:       .red
        case .starting:    .orange
        case .idle:        .gray
        }
    }

    private var statusLabel: String {
        switch service.status {
        case .listening:   "Listening on :8847"
        case .processing:  "Processing request…"
        case .error:       "Error — tap to restart"
        case .starting:    "Starting up…"
        case .idle:        "Idle"
        }
    }

    private var formattedUptime: String {
        let h = uptimeSeconds / 3600
        let m = (uptimeSeconds % 3600) / 60
        let s = uptimeSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func modelIcon(for model: String) -> String {
        let l = model.lowercased()
        if l.contains("clara")     { return "brain.head.profile" }
        if l.contains("fastvlm")   { return "eye.fill" }
        if l.contains("ml-sharp") || l.contains("splat") { return "rotate.3d" }
        if l.contains("yolo") || l.contains("vision") { return "viewfinder" }
        return "cpu.fill"
    }

    private func modelColor(for model: String) -> Color {
        let l = model.lowercased()
        if l.contains("clara")   { return .purple }
        if l.contains("fastvlm") { return .blue }
        if l.contains("sharp")   { return .orange }
        return .green
    }

    private func toggleLoginItem(enabled: Bool) {
        let smService = SMAppService.loginItem(identifier: "com.secretatomics.visualintelligence.mac.edgenode.helper")
        do {
            if enabled {
                try smService.register()
            } else {
                try smService.unregister()
            }
        } catch {
            print("❌ Login item toggle failed: \(error)")
            isLoginItemEnabled = smService.status == .enabled
        }
    }
}

// MARK: - Activity Entry

private struct ActivityEntry: Identifiable {
    let id = UUID()
    let time: Date
    let label: String
}
