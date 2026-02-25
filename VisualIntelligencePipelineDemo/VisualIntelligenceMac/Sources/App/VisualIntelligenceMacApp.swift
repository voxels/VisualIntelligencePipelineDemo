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

    private let dataStore: DiverDataStore
    private let metadataPipelineService: MetadataPipelineService
    private let keychainService: KeychainService
    private let cloudKitSyncMonitor: CloudKitSyncMonitor
    private let queueStore: DiverQueueStore?

    @State private var edgeNodeInstaller = EdgeNodeInstallService()
    @State private var showOnboarding = false

    init() {
        // 1. Initial services
        self.keychainService = KeychainService(service: KeychainService.ServiceIdentifier.diver)
        self.cloudKitSyncMonitor = CloudKitSyncMonitor()

        // 2. Define schemas matching iOS app
        let diverTypes: [any PersistentModel.Type] = DiverDataStore.coreTypes
        let knowMapsTypes: [any PersistentModel.Type] = [
            UserCachedRecord.self,
            RecommendationData.self
        ]
        let fullSchema = Schema(diverTypes + knowMapsTypes)
        
        // 3. Define Configurations with App Group
        let diverConfig: ModelConfiguration
        do {
            let appGroupURL = try AppGroupContainer.dataStoreURL()
            diverConfig = ModelConfiguration(schema: fullSchema, url: appGroupURL)
        } catch {
            print("VisualIntelligenceMacApp: Failed to get App Group URL: \(error)")
            diverConfig = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
        }
        
        // 4. Initialize DataStore
        do {
            self.dataStore = try DiverDataStore(schema: fullSchema, configurations: [diverConfig])
            UnifiedDataManager.shared = UnifiedDataManager(store: self.dataStore)
        } catch {
            print("VisualIntelligenceMacApp: Catastrophic failure initializing DataStore: \(error.localizedDescription)")
            fatalError("VisualIntelligenceMacApp: Catastrophic failure initializing DataStore: \(error.localizedDescription)")
        }

        // 5. Initialize QueueStore
        if let queueDirectory = AppGroupContainer.queueDirectoryURL() {
            self.queueStore = try? DiverQueueStore(directoryURL: queueDirectory)
        } else {
            self.queueStore = nil
        }

        // 6. Initialize Pipeline
        self.metadataPipelineService = MetadataPipelineService(
            queueStore: queueStore,
            modelContainer: dataStore.container,
            mainContext: dataStore.mainContext
        )
        
        // 6. Start Sync Monitor
        self.cloudKitSyncMonitor.start(for: nil)
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .modelContainer(dataStore.container)
                .environment(\.metadataPipelineService, metadataPipelineService)
                .environment(edgeNodeInstaller)
                .environmentObject(cloudKitSyncMonitor)
                .onAppear {
                    // Show onboarding sheet if Edge Node hasn't been registered yet
                    // Use a slight delay to ensure the window is ready
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        if !edgeNodeInstaller.hasPromptedUser {
                            showOnboarding = true
                        }
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    EdgeNodeOnboardingView(installer: edgeNodeInstaller)
                }
        }
        .commands {
            MacAppCommands()
        }
        
        Settings {
            MacSettingsView(installer: edgeNodeInstaller)
                .modelContainer(dataStore.container)
                .environment(edgeNodeInstaller)
                .environmentObject(cloudKitSyncMonitor)
        }
    }
}


