//
//  EdgeDaemonMenu.swift
//  EdgeDaemon
//
//  Menu bar popover showing edge node status, connected clients,
//  and quick actions for model management and settings.
//

import SwiftUI
import DiverKit
import DiverShared

/// Main menu bar popover view.
struct EdgeDaemonMenu: View {
    @Bindable var service: EdgeDaemonService
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                EdgeDaemonStatusBar(status: service.status)
                Spacer()
                Text("Visual Intelligence Edge")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Quick stats
            HStack(spacing: 20) {
                StatBadge(label: "Clients", value: "\(service.connectedClients.count)", icon: "iphone", color: .blue)
                StatBadge(label: "Requests", value: "\(service.totalRequests)", icon: "arrow.triangle.2.circlepath", color: .green)
                StatBadge(label: "Models", value: "\(service.loadedModels.count)", icon: "cpu", color: .purple)
            }
            .padding()
            
            Divider()
            
            // Connected clients
            if !service.connectedClients.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected Devices")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(service.connectedClients, id: \.self) { client in
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(.blue)
                            Text(client)
                                .font(.subheadline)
                            Spacer()
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
            }
            
            // Actions
            VStack(spacing: 4) {
                Button {
                    if service.isListening {
                        service.stopListening()
                    } else {
                        service.startListening()
                    }
                } label: {
                    Label(
                        service.isListening ? "Stop Serving" : "Start Serving",
                        systemImage: service.isListening ? "stop.circle" : "play.circle"
                    )
                }
                .buttonStyle(.borderless)
                
                Divider()
                
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings…", systemImage: "gear")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit Edge Daemon", systemImage: "power")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding()
        }
        .frame(width: 320)
    }
}

/// Reusable stat badge for the menu bar popover.
private struct StatBadge: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
