//
//  ReprocessingWizardView.swift
//  Diver
//
//  Created by Antigravity on 01/11/26.
//

import SwiftUI
import SwiftData
import DiverKit

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
            ProgressView()
                .scaleEffect(1.5)
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
                    indexingService: services.knowledgeGraphService // conformance?
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
