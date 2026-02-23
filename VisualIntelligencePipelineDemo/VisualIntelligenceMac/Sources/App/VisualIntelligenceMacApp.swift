//
//  VisualIntelligenceMacApp.swift
//  VisualIntelligenceMac
//
//  Entry point for the native macOS companion app.
//  On first launch, registers the embedded Edge Node as a Login Item
//  via SMAppService so it starts automatically at every login.
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import ServiceManagement

@main
struct VisualIntelligenceMacApp: App {

    @State private var dataStore = DiverDataStore()
    @State private var edgeNodeInstaller = EdgeNodeInstallService()
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environment(\.modelContext, dataStore.mainContext)
                .environmentObject(edgeNodeInstaller)
                .onAppear {
                    // Show onboarding sheet if Edge Node hasn't been registered yet
                    if !edgeNodeInstaller.hasPromptedUser {
                        showOnboarding = true
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    EdgeNodeOnboardingView(installer: edgeNodeInstaller)
                }
        }
        .commands {
            MacAppCommands()
        }
    }
}
