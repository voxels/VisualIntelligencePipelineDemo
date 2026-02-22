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
    @State private var isLoginItemEnabled = SMAppService.mainApp.status == .enabled

    var body: some Scene {
        MenuBarExtra {
            EdgeDaemonMenu(
                service: service,
                isLoginItemEnabled: $isLoginItemEnabled
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: service.isListening ? "brain.filled.head.profile" : "brain.head.profile")
                if service.status == .processing {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                }
            }
        }
    }
}

// MARK: - Menu Content

struct EdgeDaemonMenu: View {
    @Bindable var service: EdgeDaemonService
    @Binding var isLoginItemEnabled: Bool

    var body: some View {
        // ── Header ──
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("Visual Intelligence Edge")
                    .fontWeight(.semibold)
            }
            Text("\(service.status.rawValue) · Port 8847 · \(service.totalRequests) requests")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        Divider()

        // ── Models ──
        ForEach(service.loadedModels, id: \.self) { model in
            Label(model, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }

        if service.loadedModels.isEmpty {
            Label("No models", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        Divider()

        // ── Clients ──
        if service.connectedClients.isEmpty {
            Label("No clients", systemImage: "iphone.slash")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            ForEach(service.connectedClients, id: \.self) { client in
                Label(client, systemImage: "iphone.radiowaves.left.and.right")
                    .font(.caption)
            }
        }

        Divider()

        // ── Controls ──
        if service.isListening {
            Button {
                service.stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
            }
        } else {
            Button {
                service.startListening()
            } label: {
                Label("Start Listening", systemImage: "play.circle")
            }
        }

        Toggle(isOn: $isLoginItemEnabled) {
            Label("Start at Login", systemImage: "clock.badge.checkmark")
        }
        .onChange(of: isLoginItemEnabled) { _, enabled in
            toggleLoginItem(enabled: enabled)
        }

        Divider()

        Button("Quit") {
            service.stopListening()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusColor: Color {
        switch service.status {
        case .listening: .green
        case .processing: .blue
        case .error: .red
        case .starting: .orange
        case .idle: .gray
        }
    }

    private func toggleLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("❌ Login item toggle failed: \(error)")
            isLoginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
