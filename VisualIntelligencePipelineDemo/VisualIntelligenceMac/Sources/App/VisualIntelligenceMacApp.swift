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
import AppKit

@main
struct VisualIntelligenceMacApp: App {

    @State private var dataStore = DiverDataStore()
    @State private var edgeNodeInstaller = EdgeNodeInstallService()
    @State private var showOnboarding = false
    @State private var showInstaller = MacInstallerView.needsInstall

    init() {
        // Bootstrap edge services BEFORE any view is created.
        // This ensures chatVM in MacContentView gets a real AgenticSearchService,
        // not NullAgenticSearchService (which happens if we wait until .onAppear).
        bootstrapEdgeServices()
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environment(\.modelContext, dataStore.mainContext)
                .environment(edgeNodeInstaller)
                .onAppear {
                    // modelContext requires @State to be ready — set here
                    Services.shared.modelContext = dataStore.mainContext

                    // Edge node onboarding (shown after installer completes)
                    if !showInstaller && !edgeNodeInstaller.hasPromptedUser {
                        showOnboarding = true
                    }
                    // FastVLM defaults ON on Mac
                    if !FastVLMEnrichmentService.isEnabled {
                        FastVLMEnrichmentService.setEnabled(true)
                    }
                }
                // Installer blocks the main window until dismissed
                .sheet(isPresented: $showInstaller, onDismiss: {
                    if !edgeNodeInstaller.hasPromptedUser {
                        showOnboarding = true
                    }
                }) {
                    MacInstallerView()
                }
                .sheet(isPresented: $showOnboarding) {
                    EdgeNodeOnboardingView(installer: edgeNodeInstaller)
                }
        }
        .commands {
            MacAppCommands(installer: edgeNodeInstaller)
        }
    }

    // MARK: - Service Bootstrap

    /// Sets up edge discovery and agentic search ONCE at app startup.
    /// Called from init() so @State view models see real services on first render.
    private func bootstrapEdgeServices() {
        guard Services.shared.agenticSearchService == nil else { return }

        let discoveryService = BonjourDiscoveryService()
        let localName = Host.current().localizedName ?? "Visual Intelligence Mac"
        let transportLayer = NWTransportLayer(localNodeName: localName)
        let actorSystem = VisualIntelligenceActorSystem(transport: transportLayer)
        let edgeRouter = PipelineEdgeRouter(discoveryService: discoveryService)
        let searchService = AgenticSearchService(router: edgeRouter, system: actorSystem)

        Services.shared.agenticSearchService = searchService
        Services.shared.edgeRouter = edgeRouter
        Services.shared.discoveryService = discoveryService
        Services.shared.actorSystem = actorSystem

        Task {
            print("🔍 [MacApp] Starting Bonjour Edge Discovery")
            await discoveryService.startDiscovery()
        }
    }

}



// MARK: - Menu Commands

struct MacAppCommands: Commands {
    @Bindable var installer: EdgeNodeInstallService

    var body: some Commands {
        CommandMenu("Edge Node") {
            if installer.isRunning {
                Button("Disable Edge Node") {
                    installer.uninstall()
                }
            } else if installer.installStatus == .requiresApproval {
                Button("Open System Settings…") {
                    installer.openSystemSettings()
                }
            } else {
                Button("Enable Edge Node…") {
                    installer.install()
                    // Show error inline if install failed (e.g. dev build, missing bundle)
                    if let err = installer.lastError {
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.messageText = "Edge Node Setup"
                        alert.informativeText = err
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }

            Button("Open System Settings…") {
                installer.openSystemSettings()
            }
            .disabled(installer.installStatus != .requiresApproval)
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Visual Intelligence") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }
    }
}
