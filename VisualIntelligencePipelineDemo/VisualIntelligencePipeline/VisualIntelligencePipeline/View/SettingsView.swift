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

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager

    @State private var showingClearConfirmation = false
    @State private var isClearing = false
    
    @State private var showingReprocessingWizard = false
    
    @State private var showingContactPicker = false
    @State private var selectedContactName: String?
    
    // Dependencies
    private let contactService = Services.shared.contactService

    var body: some View {
        NavigationStack {
            Form {
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
                }

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
                
                // Maintenance Section
                Section {
                    Button {
                        showingReprocessingWizard = true
                    } label: {
                        Label("Reprocess Pipeline", systemImage: "arrow.triangle.2.circlepath.circle")
                    }
                    .sheet(isPresented: $showingReprocessingWizard) {
                         ReprocessingWizardView()
                    }
                } header: {
                    Text("Maintenance")
                } footer: {
                    Text("Clean up and re-run intelligence on historical items.")
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
                
                // 3. Delete KnowMaps cache/models (if present)
                try modelContext.delete(model: UserCachedRecord.self)
                try modelContext.delete(model: RecommendationData.self)

                try modelContext.save()

                await MainActor.run {
                    isClearing = false
                }

                print("✅ Database deleted successfully")
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
}

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

    SettingsView()
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

// MARK: - Maintenance View

struct ReprocessingWizardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Config
    @State private var cutoffDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    
    // State
    @State private var currentStep: WizardStep = .config
    @State private var isProcessing = false
    @State private var processingStatusMsg = ""
    @State private var reviewItems: [ProcessedItem] = []
    @State private var progress: Double = 0.0
    
    // Dependencies (Inject or use shared)
    // For simplicity using shared services here, mirroring SettingsView
    private let services = Services.shared
    
    enum WizardStep {
        case config
        case processing
        case review
        case complete
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                switch currentStep {
                case .config:
                    configView
                case .processing:
                    processingView
                case .review:
                    reviewView
                case .complete:
                    completeView
                }
            }
            .navigationTitle("Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if currentStep == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish") {
                             finishReview()
                        }
                    }
                } else if currentStep == .complete {
                     ToolbarItem(placement: .confirmationAction) {
                          Button("Done") { dismiss() }
                     }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
    
    // MARK: - Steps
    
    var configView: some View {
        Form {
            Section {
                DatePicker("Reprocess items created after:", selection: $cutoffDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
            } header: {
                Text("Configuration")
            } footer: {
                Text("This will re-run the intelligence pipeline on all matching items. Original inputs will be reconstructed from current metadata.")
            }
            
            Section {
                Button {
                    startReprocessing()
                } label: {
                    Text("Start Reprocessing")
                    .frame(maxWidth: .infinity)
                    .bold()
                }
                .listRowBackground(Color.blue)
                .foregroundStyle(.white)
            }
        }
    }
    
    var processingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress, total: 1.0) {
                 Text("\(Int(progress * 100))%")
                     .font(.caption)
                     .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal, 40)

            Text("Reprocessing Pipeline...")
                .font(.headline)
            Text(processingStatusMsg)
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
    
    var reviewView: some View {
        List {
            if reviewItems.isEmpty {
                ContentUnavailableView("No Conflicts Found", systemImage: "checkmark.circle")
            } else {
                Section {
                     Text("The system detected potential place conflicts for the following items. Please confirm the correct location and purpose.")
                         .font(.caption)
                         .foregroundStyle(.secondary)
                }
                
                ForEach(reviewItems) { item in
                    ReviewItemRow(item: item)
                }
            }
        }
    }
    
    var completeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Maintenance Complete")
                .font(.title2).bold()
            Text("All items have been reprocessed and reviewed.")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func startReprocessing() {
        currentStep = .processing
        isProcessing = true
        progress = 0.0 // Reset
        
        Task {
            do {
                let pipeline = LocalPipelineService(modelContext: modelContext)
                
                processingStatusMsg = "Starting batch job..."
                
                try await pipeline.reprocessPipeline(
                    cutoffDate: cutoffDate,
                    enrichmentService: WebViewLinkEnrichmentService(), // Use fresh instance for batch
                    // Assuming Services.shared has these properly set
                    locationService: services.locationService, // Passed for type signature, but reprocess logic passes nil internally
                    foursquareService: services.foursquareService,
                    duckDuckGoService: services.duckDuckGoService,
                    weatherService: services.weatherService,
                    activityService: services.activityService,
                    indexingService: services.knowledgeGraphService, // conformance?
                    progressHandler: { value in
                        self.progress = value
                    }
                )
                
                processingStatusMsg = "Checking for conflicts..."
                
                // Fetch items marked for review
                let fetch = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.statusRaw == "reviewRequired" }
                )
                let items = try modelContext.fetch(fetch)
                
                await MainActor.run {
                    self.reviewItems = items
                    self.currentStep = .review
                    self.isProcessing = false
                }
                
            } catch {
                await MainActor.run {
                    self.processingStatusMsg = "Error: \(error.localizedDescription)"
                    self.isProcessing = false // Stuck in error state for now
                }
            }
        }
    }
    
    private func finishReview() {
        // Mark all reviewed items as ready
        for item in reviewItems {
            item.status = .ready
        }
        try? modelContext.save()
        currentStep = .complete
    }
}

struct ReviewItemRow: View {
    @Bindable var item: ProcessedItem
    @State private var showingEdit = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title ?? "Untitled")
                .font(.headline)
            
            if let log = item.processingLog.last {
                Text(log)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
            
            HStack {
                if let place = item.placeContext?.name {
                    Label(place, systemImage: "mappin.and.ellipse")
                }
                Spacer()
                Button("Confirm & Keep") {
                    item.status = .ready
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
