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
    
    @State private var showingLogExporter = false
    @State private var exportedLogURL: URL?
    
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

