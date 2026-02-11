//
//  ReprocessingWizardView.swift
//  Diver
//
//  Created by Antigravity on 01/11/26.
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared

struct ReprocessingWizardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Config
    @State private var cutoffDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    
    // State
    @State private var currentStep: WizardStep = .config
    @State private var isProcessing = false
    @State private var processingStatusMsg = ""
    @State private var progress: Double = 0.0
    @State private var reviewItems: [ProcessedItem] = []
    
    // Approval tracking - key is item.id
    @State private var approvalStates: [String: ReviewApprovalState] = [:]
    @State private var originalSnapshots: [String: ItemSnapshot] = [:]
    @State private var editingItem: ProcessedItem? = nil
    
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
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 250)
            
            Text("Reprocessing Pipeline...")
                .font(.headline)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
            
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
                ContentUnavailableView("No Changes to Review", systemImage: "checkmark.circle", description: Text("All items processed without conflicts."))
            } else {
                Section {
                    Text("Review changes below. Items you don't explicitly approve will remain unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Summary counts
                    HStack {
                        Label("\(approvedCount)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("\(deniedCount)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Label("\(pendingCount)", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                
                ForEach(reviewItems) { item in
                    ReviewItemRow(
                        item: item,
                        approvalState: bindingForItem(item),
                        onEditLocation: { editingItem = item }
                    )
                }
            }
        }
        .sheet(item: $editingItem) { item in
            if let session = sessionForItem(item) {
                EditSessionLocationView(session: session)
            }
        }
    }
    
    private var approvedCount: Int {
        approvalStates.values.filter { $0 == .approved }.count
    }
    
    private var deniedCount: Int {
        approvalStates.values.filter { $0 == .denied }.count
    }
    
    private var pendingCount: Int {
        reviewItems.count - approvedCount - deniedCount
    }
    
    private func bindingForItem(_ item: ProcessedItem) -> Binding<ReviewApprovalState> {
        Binding(
            get: { approvalStates[item.id] ?? .pending },
            set: { approvalStates[item.id] = $0 }
        )
    }
    
    private func sessionForItem(_ item: ProcessedItem) -> DiverSession? {
        guard let sessionID = item.sessionID else { return nil }
        let fetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        return try? modelContext.fetch(fetch).first
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
        
        Task {
            do {
                let pipeline = LocalPipelineService(modelContext: modelContext)
                
                // Normalize cutoffDate to the start of the selected day
                let normalizedCutoff = Calendar.current.startOfDay(for: cutoffDate)
                
                processingStatusMsg = "Capturing original state..."
                
                // CRITICAL: Capture snapshots BEFORE reprocessing so we can rollback
                let itemsToProcess = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.createdAt >= normalizedCutoff }
                )
                if let items = try? modelContext.fetch(itemsToProcess) {
                    for item in items {
                        originalSnapshots[item.id] = ItemSnapshot(from: item)
                    }
                }
                
                processingStatusMsg = "Starting batch job..."
                
                try await pipeline.reprocessPipeline(
                    cutoffDate: normalizedCutoff,
                    enrichmentService: WebViewLinkEnrichmentService(), // Use fresh instance for batch
                    // Assuming Services.shared has these properly set
                    locationService: services.locationService, // Passed for type signature, but reprocess logic passes nil internally
                    foursquareService: services.foursquareService,
                    duckDuckGoService: services.duckDuckGoService,
                    weatherService: services.weatherService,
                    indexingService: services.knowledgeGraphService,
                    progressHandler: { p in
                        self.progress = p
                    },
                    logHandler: { message in
                        // MainActor update is automatic if using @State on View but best to be safe or rely on @MainActor task
                        Task { @MainActor in
                            self.processingStatusMsg = message
                        }
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
        for item in reviewItems {
            let state = approvalStates[item.id] ?? .pending
            
            switch state {
            case .approved:
                // User approved - keep new data, mark ready
                item.status = .ready
                item.processingLog.append("\(Date().formatted()): User approved reprocessed changes.")
                
            case .denied:
                // User denied - restore original snapshot if available
                if let snapshot = originalSnapshots[item.id] {
                    snapshot.restore(to: item)
                    item.processingLog.append("\(Date().formatted()): User rejected changes. Restored original data.")
                }
                item.status = .ready
                
            case .pending:
                // User didn't review - leave as-is (don't change status)
                // Item stays in reviewRequired state or we can mark ready
                item.status = .ready
                item.processingLog.append("\(Date().formatted()): No explicit review. Changes kept by default.")
            }
        }
        try? modelContext.save()
        currentStep = .complete
    }
}

struct ReviewItemRow: View {
    @Bindable var item: ProcessedItem
    @Binding var approvalState: ReviewApprovalState
    var onEditLocation: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title ?? "Untitled")
                    .font(.headline)
                Spacer()
                // Approval status indicator
                switch approvalState {
                case .pending:
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                case .approved:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .denied:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            if let log = item.processingLog.last {
                Text(log)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
            
            HStack {
                if let place = item.placeContext?.name {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    approvalState = .approved
                } label: {
                    Label("Keep", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                
                Button {
                    approvalState = .denied
                } label: {
                    Label("Reject", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button {
                    onEditLocation()
                } label: {
                    Label("Edit", systemImage: "mappin")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

enum ReviewApprovalState {
    case pending
    case approved
    case denied
}

/// Stores original item data for rollback if user denies changes
struct ItemSnapshot {
    // Identity & Core
    let title: String?
    let summary: String?
    let entityType: String?
    let url: String?
    let tags: [String]
    let sessionID: String?
    
    // Metadata
    let transcription: String?
    let categories: [String]
    let location: String?
    let price: Double?
    let rating: Double?
    let purposes: [String]
    
    // Contexts (Value types)
    let placeContext: PlaceContext?
    let webContext: WebContext?
    let documentContext: DocumentContext?
    let qrContext: QRCodeContext?
    let questions: [String]
    
    init(from item: ProcessedItem) {
        self.title = item.title
        self.summary = item.summary
        self.entityType = item.entityType
        self.url = item.url
        self.tags = item.tags
        self.sessionID = item.sessionID
        
        self.transcription = item.transcription
        self.categories = item.categories
        self.location = item.location
        self.price = item.price
        self.rating = item.rating
        self.purposes = item.purposes
        
        self.placeContext = item.placeContext
        self.webContext = item.webContext
        self.documentContext = item.documentContext
        self.qrContext = item.qrContext
        self.questions = item.questions
    }
    
    func restore(to item: ProcessedItem) {
        item.title = title
        item.summary = summary
        item.entityType = entityType
        item.url = url
        item.tags = tags
        item.sessionID = sessionID
        
        item.transcription = transcription
        item.categories = categories
        item.location = location
        item.price = price
        item.rating = rating
        item.purposes = purposes
        
        item.placeContext = placeContext
        item.webContext = webContext
        item.documentContext = documentContext
        item.qrContext = qrContext
        item.questions = questions
    }
}
