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
            Label("Edge Daemon", systemImage: menuBarIcon)
                .labelStyle(.iconOnly)
        }
    }

    private var menuBarIcon: String {
        switch service.status {
        case .listening: return "brain.filled.head.profile"
        case .processing: return "brain.head.profile"
        case .error: return "exclamationmark.triangle.fill"
        default: return "brain.head.profile"
        }
    }
}

// MARK: - Menu Content

struct EdgeDaemonMenu: View {
    @Bindable var service: EdgeDaemonService
    @Binding var isLoginItemEnabled: Bool

    var body: some View {
        // Status Header
        Section {
            HStack {
                Image(systemName: service.statusIcon)
                    .foregroundStyle(statusColor)
                Text(service.status.rawValue)
                    .fontWeight(.semibold)
            }

            if service.isListening {
                Label("Port 8847", systemImage: "network")
            }

            Label("\(service.totalRequests) requests", systemImage: "chart.bar.fill")
        }

        Divider()

        // Models
        Section("Models (\(service.loadedModels.count))") {
            if service.loadedModels.isEmpty {
                Text("No models loaded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.loadedModels, id: \.self) { model in
                    Label(model, systemImage: "cpu")
                }
            }
        }

        Divider()

        // Clients
        Section("Clients (\(service.connectedClients.count))") {
            if service.connectedClients.isEmpty {
                Text("No clients connected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.connectedClients, id: \.self) { client in
                    Label(client, systemImage: "iphone")
                }
            }
        }

        Divider()

        // Controls
        Section {
            Toggle(isOn: Binding(
                get: { service.isListening },
                set: { newValue in
                    if newValue {
                        service.startListening()
                    } else {
                        service.stopListening()
                    }
                }
            )) {
                Label("Listening", systemImage: "antenna.radiowaves.left.and.right")
            }

            Toggle(isOn: $isLoginItemEnabled) {
                Label("Start at Login", systemImage: "person.crop.circle.badge.clock")
            }
            .onChange(of: isLoginItemEnabled) { _, newValue in
                toggleLoginItem(enabled: newValue)
            }
        }

        Divider()

        Button("Quit Edge Daemon") {
            service.stopListening()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusColor: Color {
        switch service.status {
        case .listening: return .green
        case .processing: return .blue
        case .error: return .red
        default: return .secondary
        }
    }

    private func toggleLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("✅ Registered as login item")
            } else {
                try SMAppService.mainApp.unregister()
                print("✅ Unregistered login item")
            }
        } catch {
            print("❌ Login item toggle failed: \(error)")
            // Revert UI state
            isLoginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
