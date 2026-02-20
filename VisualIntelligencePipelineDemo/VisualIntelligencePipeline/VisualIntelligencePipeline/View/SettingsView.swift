//
//  SettingsView.swift
//  Diver
//
//  Settings and preferences
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import Contacts
import ContactsUI
import knowmaps
import CloudKit

// MARK: - Shared Download State (persists across view dismiss/re-open)
@MainActor
final class FastVLMDownloadManager: ObservableObject {
    static let shared = FastVLMDownloadManager()
    @Published var isDownloading = false
    @Published var progress: Double = 0
    private init() {}
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.metadataPipelineService) private var pipelineService
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager
    var viewModel: SidebarViewModel

    @State private var showingClearConfirmation = false
    @State private var isClearing = false
    
    @State private var showingReprocessingWizard = false
    
    @State private var showingContactPicker = false
    @State private var selectedContactName: String?
    
    @State private var showingLogExporter = false
    @State private var exportedLogURL: URL?
    
    @StateObject private var fastVLMDownload = FastVLMDownloadManager.shared
    
    // Dependencies
    private let contactService = Services.shared.contactService

    var body: some View {
        NavigationStack {
            Form {


                // Personal Information Section
                Section {
                    #if os(iOS)
                    Button {
                        showingContactPicker = true
                    } label: {
                        HStack {
                            Text("My Contact Card")
                            Spacer()
                            if let name = selectedContactName {
                                Text(name)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not Set")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .sheet(isPresented: $showingContactPicker) {
                        ContactPickerView { contact in
                            saveContact(contact)
                        }
                    }
                    #else
                    Text("Contact selection is handled automatically on macOS.")
                        .foregroundStyle(.secondary)
                    #endif
                } header: {
                    Text("Personal Information")
                } footer: {
                    Text("Select your contact card to enable home location features.")
                }

                // Automation Section
                Section {
                    NavigationLink {
                        ShortcutGalleryView()
                    } label: {
                        Label("Shortcut Gallery", systemImage: "wand.and.stars")
                            .foregroundStyle(.purple)
                    }
                } header: {
                    Text("Automation")
                } footer: {
                    Text("Discover ways to automate Diver with the Shortcuts app and Siri.")
                }
                
                // Commerce Intelligence Section
                Section {
                    NavigationLink {
                        EthicalPolicyConfigView()
                    } label: {
                        Label("Ethical Preferences", systemImage: "leaf.fill")
                            .foregroundStyle(.green)
                    }                    
                    NavigationLink {
                        OwnedProductsView()
                    } label: {
                        Label("Owned Products", systemImage: "bag.fill")
                            .foregroundStyle(.blue)
                    }
                } header: {
                    Text("Commerce Intelligence")
                } footer: {
                    Text("Configure ethical purchasing preferences, manage API keys for product data, and view owned products.")
                }
                
                // Maintenance Section
                Section {
                    Button {
                        viewModel.rebuildLibrary(context: modelContext)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Rebuild Library", systemImage: "arrow.triangle.2.circlepath.icloud")
                            if viewModel.isMaintaining {
                                Text(viewModel.maintenanceStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .disabled(viewModel.isMaintaining)
                    
                    Button {
                        showingReprocessingWizard = true
                    } label: {
                        Label("Reprocess Pipeline", systemImage: "arrow.triangle.2.circlepath.circle")
                    }
                    .sheet(isPresented: $showingReprocessingWizard) {
                         ReprocessingWizardView()
                    }
                    
                    Button {
                        exportProcessingLogs()
                    } label: {
                        Label("Export Processing Logs", systemImage: "square.and.arrow.up")
                    }
                    .sheet(isPresented: $showingLogExporter) {
                        if let url = exportedLogURL {
                            LogExportShareSheet(activityItems: [url])
                        }
                    }
                } header: {
                    Text("Maintenance")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("**Rebuild Library**: Fixes broken relationships, restores missing sessions, and regenerates summaries based on already processed data. (Fast)")
                        Text("**Reprocess Pipeline**: Re-runs the entire intelligence pipeline (OCR, analysis) on historical items. (Slow)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }

                // FastVLM On-Device Intelligence
                Section {
                    Toggle("FastVLM Vision Enrichment", isOn: Binding(
                        get: { FastVLMEnrichmentService.isEnabled },
                        set: { newValue in
                            FastVLMEnrichmentService.setEnabled(newValue)
                            if newValue {
                                if FastVLMEnrichmentService.isModelCached {
                                    // Model already downloaded — wire immediately
                                    pipelineService?.fastVLMService = FastVLMEnrichmentService()
                                } else if !fastVLMDownload.isDownloading {
                                    // Start download automatically (skip if already in progress)
                                    fastVLMDownload.isDownloading = true
                                    fastVLMDownload.progress = 0
                                    Task {
                                        // Keep download alive when app backgrounds
                                        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
                                        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "FastVLMModelDownload") {
                                            // Expiration handler — clean up if time runs out
                                            UIApplication.shared.endBackgroundTask(bgTaskID)
                                            bgTaskID = .invalid
                                        }
                                        
                                        defer {
                                            if bgTaskID != .invalid {
                                                UIApplication.shared.endBackgroundTask(bgTaskID)
                                            }
                                        }
                                        
                                        do {
                                            let service = FastVLMEnrichmentService()
                                            try await service.ensureModelAvailable { progress in
                                                Task { @MainActor in
                                                    self.fastVLMDownload.progress = progress
                                                }
                                            }
                                            fastVLMDownload.isDownloading = false
                                            pipelineService?.fastVLMService = service
                                            NotificationCenter.default.post(name: .fastVLMDownloadComplete, object: nil)
                                        } catch {
                                            fastVLMDownload.isDownloading = false
                                            FastVLMEnrichmentService.setEnabled(false)
                                            print("❌ FastVLM download failed: \(error)")
                                        }
                                    }
                                }
                            } else {
                                pipelineService?.fastVLMService = nil
                            }
                        }
                    ))
                    .tint(.purple)
                    .disabled(fastVLMDownload.isDownloading)
                    
                    if fastVLMDownload.isDownloading {
                        HStack {
                            ProgressView(value: fastVLMDownload.progress)
                                .tint(.purple)
                            Text("\(Int(fastVLMDownload.progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else if FastVLMEnrichmentService.isEnabled && FastVLMEnrichmentService.isModelCached {
                        HStack {
                            Label("Model Ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Delete Model") {
                                try? FastVLMEnrichmentService().deleteModel()
                                pipelineService?.fastVLMService = nil
                                FastVLMEnrichmentService.setEnabled(false)
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("On-Device Intelligence")
                } footer: {
                    Text("Uses Apple FastVLM to analyze captured images directly on-device for richer descriptions. Requires ~500 MB of storage for the model.")
                }

                Section {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        if isClearing {
                            HStack {
                                Text("Deleting Database...")
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else {
                            Label("Delete Database", systemImage: "trash")
                        }
                    }
                    .disabled(isClearing)

                    StorageInfoRow()
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Permanently deletes all items, references, concepts, and relationships. This provides a fresh start.")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
                
                // Shared with You Section
                Section {
                    if #available(iOS 16.0, macOS 13.0, *) {
                        Toggle("Shared with You", isOn: Binding(
                            get: { sharedWithYouManager.isEnabled },
                            set: { sharedWithYouManager.setEnabled($0) }
                        ))
                        .tint(.blue)

                        if sharedWithYouManager.isEnabled {
                            Text("Automatically save links shared in Messages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Shared with You requires iOS 16+ or macOS 13+")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Features")
                } footer: {
                    if sharedWithYouManager.isEnabled {
                        Text("To see shared links, ensure 'Shared with You' is enabled in Settings > Messages > Shared with You.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Database?", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteDatabase()
                }
            } message: {
                Text("This will permanently remove all of your data, including captured items, search history, and generated concepts. This action cannot be undone.")
            }
            .onAppear {
                loadCurrentContact()
            }

        }
    }



    private func deleteDatabase() {
        isClearing = true

        Task {
            do {
                // 0. Clear the DiverQueueStore (processing queue)
                try? sharedWithYouManager.clearQueueStore()
                print("✅ Cleared DiverQueueStore")
                
                // 1. Clear Main App Group Container (Documents, Queue, etc.)
                if let appGroupURL = try? AppGroupContainer.containerURL() {
                    let fileManager = FileManager.default
                    // We specifically target the 'Documents' and 'Queue' folders where source files live.
                    let targetDirs = ["Documents", "Queue", "SourceImages", "Snapshots"]
                    
                    for dirName in targetDirs {
                        let dirURL = appGroupURL.appendingPathComponent(dirName, isDirectory: true)
                        if fileManager.fileExists(atPath: dirURL.path) {
                             try? fileManager.removeItem(at: dirURL)
                             print("✅ Deleted AppGroup Directory: \(dirName)")
                        }
                    }
                    
                    // Also clear root files that look like orphaned images or JSON
                    if let contents = try? fileManager.contentsOfDirectory(at: appGroupURL, includingPropertiesForKeys: nil) {
                        for url in contents {
                            if ["jpg", "jpeg", "png", "json", "txt"].contains(url.pathExtension.lowercased()) {
                                try? fileManager.removeItem(at: url)
                            }
                        }
                    }
                }
                
                // 2. Delete all main entities
                try modelContext.delete(model: ProcessedItem.self)
                try modelContext.delete(model: LocalInput.self)
                try modelContext.delete(model: UserConcept.self)
                
                // 3. Delete sessions and collections
                try modelContext.delete(model: SessionMetadata.self)
                try modelContext.delete(model: SessionCollection.self)
                
                // 4. Delete KnowMaps cache/models (if present)
                try modelContext.delete(model: UserCachedRecord.self)
                try modelContext.delete(model: RecommendationData.self)

                try modelContext.save()
                
                // Give CloudKit time to sync deletions
                print("⏳ Waiting for CloudKit sync...")
                try await Task.sleep(for: .seconds(2))
                
                // Fallback: Purge CloudKit zone directly for orphaned records
                await purgeCloudKitZone()

                await MainActor.run {
                    isClearing = false
                }

                print("✅ Database deleted successfully (all local and cloud entities)")
            } catch {
                await MainActor.run {
                    isClearing = false
                }
                print("❌ Failed to delete database: \(error)")
            }
        }
    }

    private func saveContact(_ contact: CNContact) {
        let formatter = CNContactFormatter()
        let name = formatter.string(from: contact)
        selectedContactName = name
        
        contactService?.setMeContact(contact.identifier)
        
        // Request access immediately so we can fetch details later
        Task {
            _ = await contactService?.requestAccess()
        }
    }
    
    private func loadCurrentContact() {
        if let identifier = contactService?.getMeContactIdentifier() {
            // Need to fetch name to display
            Task {
                let store = CNContactStore()
                do {
                    let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)])
                    let formatter = CNContactFormatter()
                    if let name = formatter.string(from: contact) {
                         await MainActor.run {
                             self.selectedContactName = name
                         }
                    }
                } catch {
                    print("Failed to fetch saved contact name: \(error)")
                }
            }
        }
    }
    
    /// Purges CloudKit zone data for orphaned records that SwiftData deletion missed
    private func purgeCloudKitZone() async {
        // 1. Use proper KnowMaps API to delete user cached records
        if let cacheService = Services.shared.cloudCacheService as? CloudCacheService {
            do {
                try await cacheService.deleteAllUserCachedGroups()
                print("✅ Deleted all user cached groups via CloudCacheService")
            } catch {
                print("⚠️ CloudCacheService deletion failed: \(error.localizedDescription)")
            }
        }
        
        // 2. Also purge direct CloudKit records for orphaned SwiftData entities
        let container = CKContainer(identifier: "iCloud.com.secretatomics.knowmaps.Cache")
        let database = container.privateCloudDatabase
        
        // Query and delete all records of each type
        let recordTypes = ["CD_ProcessedItem", "CD_SessionMetadata", "CD_UserConcept", "CD_LocalInput", "CD_SessionCollection"]
        
        for recordType in recordTypes {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (results, _) = try await database.records(matching: query)
                
                let recordIDs = results.compactMap { try? $0.1.get().recordID }
                
                if !recordIDs.isEmpty {
                    let (_, deleteErrors) = try await database.modifyRecords(saving: [], deleting: recordIDs)
                    if deleteErrors.isEmpty {
                        print("✅ Purged \(recordIDs.count) CloudKit records of type: \(recordType)")
                    } else {
                        print("⚠️ Partial delete for \(recordType): \(deleteErrors)")
                    }
                }
            } catch {
                // Record type may not exist in this container, which is fine
                print("ℹ️ CloudKit purge for \(recordType): \(error.localizedDescription)")
            }
        }
    }
    private func exportProcessingLogs() {
        Task {
            do {
                let descriptor = FetchDescriptor<ProcessedItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                let items = try modelContext.fetch(descriptor)
                
                let exports = items.map { item in
                    LogExport(
                        id: item.id,
                        title: item.title,
                        createdAt: item.createdAt,
                        logs: item.processingLog
                    )
                }
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(exports)
                
                let dateString = Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")
                let filename = "diver_processing_logs_\(dateString).json"
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(filename)
                
                try data.write(to: fileURL)
                
                await MainActor.run {
                    self.exportedLogURL = fileURL
                    self.showingLogExporter = true
                }
            } catch {
                print("Failed to export logs: \(error)")
            }
        }
    }
}

struct LogExport: Codable {
    let id: String
    let title: String?
    let createdAt: Date
    let logs: [String]
}

#if os(iOS)
struct LogExportShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct LogExportShareSheet: View {
    var activityItems: [Any]
    var body: some View {
        VStack {
            Text("Export Ready")
                .font(.headline)
            if let url = activityItems.first as? URL {
                ShareLink(item: url) {
                    Label("Save or Share JSON", systemImage: "square.and.arrow.up")
                }
                .padding()
                
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 150)
    }
}
#endif
struct StorageInfoRow: View {
    @Query private var processedItems: [ProcessedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Processed Items")
                Spacer()
                Text("\(processedItems.count)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

#Preview {
    @Previewable @State var manager: SharedWithYouManager = {
        let queueDir = FileManager.default.temporaryDirectory.appendingPathComponent("preview-queue")
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        let queueStore = try! DiverQueueStore(directoryURL: queueDir)
        return SharedWithYouManager(queueStore: queueStore, isEnabled: true)
    }()

    SettingsView(viewModel: SidebarViewModel())
        .modelContainer(for: [ProcessedItem.self], inMemory: true)
        .environmentObject(manager)
}

#if os(iOS)
struct ContactPickerView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var onSelect: (CNContact) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Allow all contacts for now, or filter if necessary. 
        // Previously: picker.predicateForEnablingContact = NSPredicate(format: "postalAddresses.@count > 0")
        // Relaxing this to allow any contact to be associated.
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPickerView

        init(_ parent: ContactPickerView) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onSelect(contact)
            parent.presentationMode.wrappedValue.dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
#endif

