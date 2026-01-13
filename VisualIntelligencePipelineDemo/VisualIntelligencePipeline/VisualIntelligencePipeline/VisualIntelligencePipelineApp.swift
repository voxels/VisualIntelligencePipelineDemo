//
//  VisualIntelligencePipelineApp.swift
//  Diver
//
//  Created by Michael A Edgcumbe on 12/22/25.
//

import SwiftUI
import DiverShared
import DiverKit // Import DiverKit for MetadataPipelineService and UnifiedDataManager
import SwiftData
import BackgroundTasks // Import BackgroundTasks
import CryptoKit
import knowmaps
import WidgetKit // Import WidgetKit for widget refresh
#if os(iOS)
import UIKit
#endif

@main
struct VisualIntelligencePipelineApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // Static service identifiers
    static let backgroundTaskIdentifier = "com.secretatomics.Diver.processQueue"
    static let diverLinkSecretKey = KeychainService.Keys.diverLinkSecret

    let dataStore: DiverDataStore
    let metadataPipelineService: MetadataPipelineService
    let keychainService: KeychainService
    
//    // Persistent enrichment services
//    private let yahooURLService = YahooLinkEnrichmentService()

    // This is where KnowMapsServiceContainer needs a ModelContext, it can use the DiverDataStore's container
    @State private var knowMapsServices: KnowMapsServiceContainer?

    // Shared with You manager (iOS 16+, macOS 13+)
    @State private var sharedWithYouManager: SharedWithYouManager?
    
    
    // Navigation Manager for deep linking
    @StateObject private var navigationManager = NavigationManager()
    
    static var sharedDataStore: DiverDataStore? {
        return _staticDataStore
    }

    static var _staticDataStore: DiverDataStore?

    init() {
        // Define schemas
        let diverTypes: [any PersistentModel.Type] = DiverDataStore.coreTypes
        let knowMapsTypes: [any PersistentModel.Type] = [
            UserCachedRecord.self,
            RecommendationData.self
        ]
        let fullSchema = Schema(diverTypes + knowMapsTypes)
        
        // Define Configurations
        // Both configurations need the FULL schema to allow cross-referencing
        // 1. Diver Config (App Group) - primary storage
        let diverConfig: ModelConfiguration
        do {
            let appGroupURL = try AppGroupContainer.dataStoreURL()
            diverConfig = ModelConfiguration(schema: fullSchema, url: appGroupURL)
        } catch {
            fatalError("VisualIntelligencePipelineApp: Failed to get App Group URL: \(error)")
        }
        
        // Initialize DataStore with dual configurations
        self.dataStore = DiverDataStore(schema: fullSchema, configurations: [diverConfig])
        VisualIntelligencePipelineApp._staticDataStore = self.dataStore
        
        // Ensure UnifiedDataManager uses the SAME store (Dual Container Consolidation)
        UnifiedDataManager.shared = UnifiedDataManager(store: self.dataStore)
        
        // Initialize MetadataPipelineService
        // It needs a queueStore (from AppGroup) and the modelContext from dataStore
        let queueDirectory = AppGroupContainer.queueDirectoryURL()!
        let queueStore = try! DiverQueueStore(directoryURL: queueDirectory)
        
        // Initialize Enrichment Services
        let locationService = LocationService()
        let contactService = ContactService()
        let weatherService = WeatherEnrichmentService()
        let activityService = ActivityEnrichmentService()
        
        // Use placeholders for API keys for now
        let foursquareContextService = FoursquareEnrichmentService(apiKey: "FOURSQUARE_API_KEY")
        let duckDuckGoContextService = DuckDuckGoEnrichmentService()
        let webViewService = WebViewLinkEnrichmentService()
        let appleMusicService = AppleMusicEnrichmentService()
        
        // Composite Link Enrichment: Prioritize Apple Music, then fallback to generic Web View
        let compositeLinkService = CompositeLinkEnrichmentService(services: [
            appleMusicService,
            webViewService
        ])
        
        let contextService = ContextQuestionService()
        let dailyContextService = DailyContextService()
        
        // Register in shared Services singleton for VisualIntelligenceViewModel
        Services.shared.locationService = locationService
        Services.shared.foursquareService = foursquareContextService
        Services.shared.duckDuckGoService = duckDuckGoContextService
        Services.shared.contactService = contactService
        Services.shared.weatherService = weatherService
        Services.shared.activityService = activityService
        Services.shared.contextQuestionService = contextService
        Services.shared.dailyContextService = dailyContextService
        Services.shared.mapKitService = MapKitEnrichmentService()
        
//        // Initially use only Yahoo URL service
//        let initialEnrichment = CompositeLinkEnrichmentService(services: [duckDuckGoContextService])
        
        self.metadataPipelineService = MetadataPipelineService(
            queueStore: queueStore,
            modelContext: dataStore.mainContext,
            enrichmentService: compositeLinkService,
            locationService: locationService,
            foursquareService: foursquareContextService,
            duckDuckGoService: duckDuckGoContextService,
            weatherService: weatherService,
            activityService: activityService,
            contextService: contextService
        )

        // Initialize KeychainService with app group
        self.keychainService = KeychainService(service: KeychainService.ServiceIdentifier.diver, accessGroup: AppGroupConfig.default.keychainAccessGroup)

        // Register background tasks
        let service = self.metadataPipelineService
        BGTaskScheduler.shared.register(forTaskWithIdentifier: VisualIntelligencePipelineApp.backgroundTaskIdentifier, using: nil) { task in
            VisualIntelligencePipelineApp.handleAppRefresh(task: task as! BGAppRefreshTask, service: service)
        }

        // Generate and store a cryptographically secure random secret if it doesn't exist
        if keychainService.retrieveString(key: VisualIntelligencePipelineApp.diverLinkSecretKey) == nil {
            let secret = Self.generateSecureSecret()
            do {
                try keychainService.store(key: VisualIntelligencePipelineApp.diverLinkSecretKey, value: secret)
                print("✅ Generated new DiverLink secret: \(secret.prefix(20))... and stored in keychain")
                print("   Keychain service: \(KeychainService.ServiceIdentifier.diver)")
                print("   Keychain access group: \(AppGroupConfig.default.keychainAccessGroup)")
            } catch {
                print("❌ Failed to store DiverLink secret: \(error)")
            }
        } else {
            print("✅ DiverLink secret already exists in keychain")
        }


    }

    var body: some Scene {
        WindowGroup {
            ContentView(pipelineService: metadataPipelineService)
                .modelContainer(dataStore.container) // Provide SwiftData container for @Query support
                .environment(\.metadataPipelineService, metadataPipelineService)
                .environmentObject(sharedWithYouManager ?? SharedWithYouManager(queueStore: try! DiverQueueStore(directoryURL: AppGroupContainer.queueDirectoryURL()!), pipelineService: metadataPipelineService, isEnabled: false))
                .environmentObject(navigationManager)
                .onAppear {
                    // Initialize KnowMapsServiceContainer with the shared container
                    knowMapsServices = {
                        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                            return nil
                        }
                        return KnowMapsServiceContainer(container: dataStore.container)
                    }()
                    
                    if let services = knowMapsServices {
                        // Update pipeline with knowmaps-backed Foursquare enrichment and Location
                        metadataPipelineService.enrichmentService = CompositeLinkEnrichmentService(
                            services: [DuckDuckGoEnrichmentService(), services.foursquareEnrichmentService]
                        )
                        metadataPipelineService.locationService = services.locationProvider
                        Services.shared.locationService = services.locationProvider
                        Services.shared.foursquareService = services.foursquareEnrichmentService
                        
                        // Initialize Knowledge Graph Adapter
                        let unifiedAdapter = KnowMapsUnifiedAdapter(container: services)
                        Services.shared.knowledgeGraphService = unifiedAdapter
                        metadataPipelineService.indexingService = unifiedAdapter
                    }

                    // Initialize SharedWithYouManager (iOS 16+, macOS 13+)
                    if #available(iOS 16.0, macOS 13.0, *) {
                        if sharedWithYouManager == nil {
                            let queueDirectory = AppGroupContainer.queueDirectoryURL()!
                            let queueStore = try! DiverQueueStore(directoryURL: queueDirectory)
                            sharedWithYouManager = SharedWithYouManager(queueStore: queueStore, pipelineService: metadataPipelineService, isEnabled: true)
                        }
                    }
                }
                .onAppear {
                    handlePendingMessagesLaunch()

                    Task {
                        do {
                            // Seed data if empty
                            try await MainActor.run {
                                try DataSeeder.seed(context: dataStore.mainContext)
                            }
                        } catch {
                            print("Data seeding failed: \(error)")
                        }
                    }
                }
                .onAppear {
                    // Process queue when app launches
                    Task {
                        try? await metadataPipelineService.processPendingQueue()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openVisualIntelligence)) { _ in
                    navigationManager.isScanActive = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .diverQueueDidUpdate)) { _ in
                    Task {
                        try? await metadataPipelineService.processPendingQueue()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.secretatomics.dailyContextUpdated"))) { _ in
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                VisualIntelligencePipelineApp.scheduleAppRefresh()
            } else if newPhase == .active {
                handlePendingMessagesLaunch()
                // Refresh Shared with You highlights when app becomes active
                if #available(iOS 16.0, macOS 13.0, *) {
                    sharedWithYouManager?.refreshHighlights()
                }
                
                // Process queue when app enters foreground
                Task {
                    try? await metadataPipelineService.processPendingQueue()
                    // Run Data Diagnostics to reassure user
                    await metadataPipelineService.runDataDiagnostics()
                }

                // Check for Daily Narrative Backfill
                // If the app was closed and we missed adding items to the daily log, catch up now.
                Task { @MainActor in
                    if let service = Services.shared.dailyContextService, !service.hasContent {
                        print("📝 Daily Context is empty, checking for backfill items...")
                        let calendar = Calendar.current
                        let startOfDay = calendar.startOfDay(for: Date())
                        
                        let descriptor = FetchDescriptor<ProcessedItem>(
                            predicate: #Predicate { $0.createdAt >= startOfDay },
                            sortBy: [SortDescriptor(\.createdAt)]
                        )
                        
                        do {
                            let items = try dataStore.mainContext.fetch(descriptor)
                            if !items.isEmpty {
                                print("📝 Found \(items.count) items to backfill daily context.")
                                let logs = items.map { item in
                                    let time = item.createdAt.formatted(date: .omitted, time: .shortened)
                                    return "[\(time)] Captured: \(item.title ?? "Untitled Item")"
                                }
                                service.ingest(logs)
                            }
                        } catch {
                            print("❌ Failed to fetch items for daily context backfill: \(error)")
                        }
                    }
                }

                // Refresh all widgets
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    static func handleAppRefresh(task: BGAppRefreshTask, service: MetadataPipelineService) {
        // Schedule next refresh first
        scheduleAppRefresh()

        // Use a Task for async work and .setTaskCompleted always
        let workTask = Task { @MainActor in
            do {
                // 1. Process Shared with You (iOS 16+)
                if #available(iOS 16.0, macOS 13.0, *) {
                    print("🔄 Checking Shared with You links...")
                    do {
                         let queueDir = AppGroupContainer.queueDirectoryURL()!
                         let qStore = try DiverQueueStore(directoryURL: queueDir)
                         // Initialize temporary manager
                         let manager = SharedWithYouManager(queueStore: qStore, pipelineService: service, isEnabled: true)
                         
                         if let store = VisualIntelligencePipelineApp.sharedDataStore {
                             await manager.processUnprocessedHighlights(modelContext: store.mainContext)
                         }
                    } catch {
                        print("❌ Failed to process Shared with You in BG: \(error)")
                    }
                }
                
                // 2. Process Queue
                try await service.processPendingQueue()
                try await service.refreshProcessedItems()
                
                task.setTaskCompleted(success: true)
                print("✅ Background queue processes completed.")
            } catch {
                print("❌ Error processing background queue: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        // Expiration handler
        task.expirationHandler = {
            print("⚠️ BGTask expired before completion.")
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: VisualIntelligencePipelineApp.backgroundTaskIdentifier)
        // Fetch no earlier than 15 minutes from now.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background task scheduled successfully.")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    /// Generates a cryptographically secure random secret for DiverLink HMAC signing
    static func generateSecureSecret() -> String {
        // Generate 32 bytes (256 bits) of random data
        let randomBytes = SymmetricKey(size: .bits256)

        // Convert to base64 string for keychain storage
        let data = randomBytes.withUnsafeBytes { Data($0) }
        return data.base64EncodedString()
    }

    private func handleDeepLink(_ url: URL) {
        print("🔗 Handling deep link: \(url.absoluteString)")
        
        // Handle secretatomics:// scheme
        if url.scheme == "secretatomics" {
            // secretatomics://open?id=...
            if url.host == "open" {
                handleOpenItem(url)
            } else if url.host == "open-messages" {
                handleDiverScheme(url)
            } else if url.host == "save-clipboard" {
                handleSaveFromClipboard()
            } else if url.host == "open-recent" {
                handleOpenRecent()
            } else if url.host == "scan" {
                handleScanScreen()
            }
            return // Return after handling a diver scheme
        }

        // Handle https://secretatomics.com/w/* (Universal Links for wrapped URLs)
        if url.host == "secretatomics.com", url.pathComponents.contains("w") {
            handleWrappedLink(url)
            return
        }
    }
    
    private func handleOpenItem(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            print("❌ Invalid deep link URL: \(url.absoluteString)")
            return
        }
        
        print("🔍 Attempting to open item with ID: \(id)")
        
        Task {
            let fetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.id == id }
            )
            
            do {
                if let item = try dataStore.mainContext.fetch(fetch).first {
                    print("✅ Found item for deep link: \(item.title ?? "Untitled")")
                    await MainActor.run {
                        navigationManager.selection = item
                    }
                } else {
                    print("⚠️ Item not found for ID: \(id)")
                    // Optional: Trigger a fetch or show an error
                }
            } catch {
                print("❌ Failed to fetch item for deep link: \(error)")
            }
        }
    }

    private func handleDiverScheme(_ url: URL) {
        guard url.host == "open-messages" else { return }
        #if os(iOS)
        var body: String?
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            body = components.queryItems?.first(where: { $0.name == "body" })?.value
        }

        var smsComponents = URLComponents()
        smsComponents.scheme = "sms"
        if let body, !body.isEmpty {
            smsComponents.queryItems = [URLQueryItem(name: "body", value: body)]
        }

        if let messagesURL = smsComponents.url {
            UIApplication.shared.open(messagesURL, options: [:], completionHandler: nil)
        }
        #endif
    }

    private func handleWrappedLink(_ url: URL) {
        print("📎 Handling wrapped link: \(url.absoluteString)")

        Task {
            do {
                // Get keychain secret
                guard let secretString = keychainService.retrieveString(key: VisualIntelligencePipelineApp.diverLinkSecretKey),
                      let secret = Data(base64Encoded: secretString) else {
                    print("❌ No keychain secret found for unwrapping")
                    return
                }

                // Parse and verify the wrapped link
                let parsed = try DiverLinkWrapper.parse(url)
                guard DiverLinkWrapper.verify(parsed, secret: secret) else {
                    print("❌ Invalid signature on wrapped link")
                    return
                }

                print("✅ Unwrapped link - ID: \(parsed.id), has payload: \(parsed.payload != nil)")

                // Try to find existing item by ID
                let linkId = parsed.id
                let fetch = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.id == linkId }
                )

                let existing = try dataStore.mainContext.fetch(fetch).first

                if let existing {
                    // Item exists - we could navigate to it in the UI
                    print("✅ Found existing item: \(existing.title ?? "Untitled")")
                    
                    // Navigate to item
                    await MainActor.run {
                        self.navigationManager.selection = existing
                    }
                } else {
                    // Item doesn't exist - extract URL from payload and enqueue
                    if let payload = try DiverLinkWrapper.resolvePayload(from: url, secret: secret),
                       let originalURL = payload.resolvedURL {
                        
                        // Guard against recursion
                        if originalURL.absoluteString == url.absoluteString {
                            print("⚠️ Recursion detected: Wrapped link points to itself. Aborting.")
                            return
                        }
                        
                        // Guard against internal scheme loops
                        if originalURL.scheme == "secretatomics" {
                             print("⚠️ Recursion prevention: Ignoring nested diver scheme link.")
                             return
                        }

                        print("📥 Enqueueing new item from wrapped link: \(originalURL.absoluteString)")

                        let descriptor = DiverItemDescriptor(
                            id: parsed.id,
                            url: originalURL.absoluteString,
                            title: payload.title ?? "Shared Link",
                            descriptionText: nil,
                            styleTags: [],
                            categories: ["deep_link"],
                            type: .web
                        )

                        let queueItem = DiverQueueItem(action: "process", descriptor: descriptor, source: "deep_link")
                        let queueDirectory = AppGroupContainer.queueDirectoryURL()!
                        let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
                        _ = try queueStore.enqueue(queueItem)

                        print("✅ Enqueued wrapped link for processing")
                    } else {
                        print("⚠️ No payload found in wrapped link, cannot extract original URL")
                    }
                }
            } catch {
                print("❌ Failed to handle wrapped link: \(error)")
            }
        }
    }

    private func handlePendingMessagesLaunch() {
        #if os(iOS)
        guard let request = MessagesLaunchStore.consume() else { return }

        var components = URLComponents()
        components.scheme = "sms"
        if let body = request.body, !body.isEmpty {
            components.queryItems = [URLQueryItem(name: "body", value: body)]
        }
        if let url = components.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        #endif
    }

    private func handleSaveFromClipboard() {
        print("📥 Deep Link: Handling save-clipboard")
        #if os(iOS)
        guard let clipboardString = UIPasteboard.general.string,
              let url = URL(string: clipboardString),
              Validation.isValidURL(clipboardString) else {
            print("⚠️ Save-clipboard: No valid URL in clipboard")
            return
        }

        print("📥 Save-clipboard: Found URL: \(url.absoluteString)")

        let descriptor = DiverItemDescriptor(
            id: DiverLinkWrapper.id(for: url),
            url: url.absoluteString,
            title: url.host ?? url.absoluteString,
            categories: ["clipboard"]
        )

        Task {
            do {
                let queueDir = AppGroupContainer.queueDirectoryURL()!
                let queueStore = try DiverQueueStore(directoryURL: queueDir)
                let queueItem = DiverQueueItem(
                    action: "save",
                    descriptor: descriptor,
                    source: "widget_action"
                )
                try queueStore.enqueue(queueItem)
                print("✅ Save-clipboard: Enqueued successfully")
                
                // Process immediately
                try await metadataPipelineService.processPendingQueue()
                
                // Refresh widgets
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                print("❌ Save-clipboard: Failed to save: \(error)")
            }
        }
        #endif
    }

    private func handleOpenRecent() {
        print("🔘 Deep Link: Handling open-recent")
        Task {
            let fetch = FetchDescriptor<ProcessedItem>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )

            do {
                if let latest = try dataStore.mainContext.fetch(fetch).first(where: { processedItem in
                    processedItem.status == .ready
                }) {
                    print("✅ Found recent item: \(latest.title ?? "Untitled"), isShared: \(latest.attributionID != nil)")
                    await MainActor.run {
                        navigationManager.selection = latest
                    }
                } else {
                    print("⚠️ Open-recent: No items found")
                }
            } catch {
                print("❌ Open-recent: Fetch failed: \(error)")
            }
        }
    }

    private func handleScanScreen() {
        print("🔍 Deep Link: Handling scan-screen")
        Task { @MainActor in
            navigationManager.isScanActive = true
        }
    }
}
