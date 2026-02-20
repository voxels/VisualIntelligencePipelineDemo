//
//  EdgeDaemonApp.swift
//  EdgeDaemon
//
//  macOS menu bar app that serves as an ML edge node for the
//  Visual Intelligence pipeline. Runs headless (no dock icon),
//  advertises via Bonjour, and accepts distributed actor calls
//  from iOS clients for Vision/VLM inference offloading.
//

import SwiftUI
import DiverKit

@main
struct EdgeDaemonApp: App {
    @State private var service = EdgeDaemonService()
    
    var body: some Scene {
        // Menu bar extra — no dock icon, lives in the menu bar
        MenuBarExtra("Visual Intelligence Edge", systemImage: service.statusIcon) {
            EdgeDaemonMenu(service: service)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window (opened via menu)
        Settings {
            EdgeDaemonSettingsView(service: service)
        }
    }
}
