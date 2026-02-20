//
//  EdgeDaemonSettingsView.swift
//  EdgeDaemon
//
//  Settings for the edge daemon: auto-start, port, model selection,
//  resource limits, and network configuration.
//

import SwiftUI
import DiverKit

/// Edge daemon settings view.
struct EdgeDaemonSettingsView: View {
    @Bindable var service: EdgeDaemonService
    @AppStorage("autoStartDaemon") private var autoStart = true
    @AppStorage("maxConcurrent") private var maxConcurrent = 4
    @AppStorage("enableLogging") private var enableLogging = true
    
    var body: some View {
        TabView {
            // General
            Form {
                Section("Startup") {
                    Toggle("Start serving on launch", isOn: $autoStart)
                    Toggle("Show in Dock", isOn: .constant(false))
                        .disabled(true)
                        .help("Edge Daemon runs as a menu bar app only")
                }
                
                Section("Performance") {
                    Stepper("Max concurrent requests: \(maxConcurrent)", value: $maxConcurrent, in: 1...16)
                    
                    LabeledContent("Neural Engine") {
                        Text("\(String(format: "%.0f", 11.0)) TOPS")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Logging") {
                    Toggle("Enable request logging", isOn: $enableLogging)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            // Models
            ModelManagerView(loadedModels: service.loadedModels)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
            
            // Network
            Form {
                Section("Bonjour") {
                    LabeledContent("Service Type") {
                        Text("_visualintel._tcp")
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Port") {
                        Text("8847")
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(service.isListening ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(service.isListening ? "Advertising" : "Not advertising")
                        }
                    }
                }
                
                Section("Security") {
                    LabeledContent("Encryption") {
                        Text("TLS 1.3")
                    }
                    LabeledContent("Authentication") {
                        Text("Peer-to-peer (local network)")
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Network", systemImage: "network")
            }
        }
        .frame(width: 450, height: 350)
    }
}
