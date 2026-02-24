//
//  MacReprocessingView.swift
//  VisualIntelligenceMac
//
//  Full 4-step reprocessing wizard — 1:1 with iOS ReprocessingWizardView.
//  Steps: Config → Processing → Review → Complete
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared

struct MacReprocessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Step { case config, processing, review, complete }

    @State private var step: Step = .config
    @State private var cutoffDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var statusMsg = ""
    @State private var reviewItems: [ProcessedItem] = []
    @State private var approvalStates: [String: ReviewApproval] = [:]
    @State private var snapshots: [String: MacItemSnapshot] = [:]

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .config:    configStep
                case .processing: processingStep
                case .review:    reviewStep
                case .complete:  completeStep
                }
            }
            .navigationTitle("Reprocess Pipeline")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .complete {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .review {
                        Button("Finish") { finishReview() }
                    } else if step == .complete {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: Steps

    private var configStep: some View {
        Form {
            Section {
                DatePicker("Reprocess items created after:",
                           selection: $cutoffDate, displayedComponents: [.date])
            } header: {
                Text("Configuration")
            } footer: {
                Text("Re-runs the full intelligence pipeline (OCR, Vision, SLM, FastVLM) on all matching items.")
            }

            Section {
                Button { startReprocessing() } label: {
                    Text("Start Reprocessing")
                        .frame(maxWidth: .infinity).bold()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }

    private var processingStep: some View {
        VStack(spacing: 24) {
            ProgressView(value: progress).progressViewStyle(.linear).frame(maxWidth: 360)
            Text("Reprocessing Pipeline…").font(.title3.bold())
            Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
            Text(statusMsg).foregroundStyle(.secondary).font(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reviewItems.isEmpty {
                ContentUnavailableView(
                    "No Changes to Review",
                    systemImage: "checkmark.circle",
                    description: Text("All items processed without conflicts.")
                )
            } else {
                HStack(spacing: 16) {
                    Label("\(approvedCount)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label("\(deniedCount)", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    Label("\(pendingCount)", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding()

                Divider()

                List(reviewItems) { item in
                    MacReviewRow(
                        item: item,
                        approval: approvalBinding(for: item)
                    )
                }
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60)).foregroundStyle(.green)
            Text("Reprocessing Complete").font(.title2.bold())
            Text("All items have been reprocessed and reviewed.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Counts

    private var approvedCount: Int { approvalStates.values.filter { $0 == .approved }.count }
    private var deniedCount:   Int { approvalStates.values.filter { $0 == .denied  }.count }
    private var pendingCount:  Int { reviewItems.count - approvedCount - deniedCount }

    private func approvalBinding(for item: ProcessedItem) -> Binding<ReviewApproval> {
        Binding(
            get: { approvalStates[item.id] ?? .pending },
            set: { approvalStates[item.id] = $0 }
        )
    }

    // MARK: Actions

    private func startReprocessing() {
        step = .processing
        Task {
            let pipeline = LocalPipelineService(modelContext: modelContext)
            let cutoff = Calendar.current.startOfDay(for: cutoffDate)

            if let items = try? modelContext.fetch(
                FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.createdAt >= cutoff })
            ) {
                for item in items { snapshots[item.id] = MacItemSnapshot(from: item) }
            }

            do {
                try await pipeline.reprocessPipeline(
                    cutoffDate: cutoff,
                    enrichmentService: WebViewLinkEnrichmentService(),
                    locationService: Services.shared.locationService,
                    indexingService: Services.shared.knowledgeGraphService,
                    progressHandler: { p in Task { @MainActor in progress = p } },
                    logHandler: { msg in Task { @MainActor in statusMsg = msg } }
                )

                let items = (try? modelContext.fetch(
                    FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.statusRaw == "reviewRequired" })
                )) ?? []

                await MainActor.run { reviewItems = items; step = .review }
            } catch {
                await MainActor.run { statusMsg = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func finishReview() {
        for item in reviewItems {
            switch approvalStates[item.id] ?? .pending {
            case .approved:
                item.status = .ready
                item.processingLog.append("\(Date().formatted()): Approved reprocessed changes.")
            case .denied:
                snapshots[item.id]?.restore(to: item)
                item.status = .ready
                item.processingLog.append("\(Date().formatted()): Rejected changes. Restored original.")
            case .pending:
                item.status = .ready
                item.processingLog.append("\(Date().formatted()): No review. Changes kept by default.")
            }
        }
        Task { @MainActor in try? modelContext.save() }
        step = .complete
    }
}

// MARK: - Review Row

private struct MacReviewRow: View {
    let item: ProcessedItem
    @Binding var approval: ReviewApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title ?? "Untitled").font(.headline)
                Spacer()
                approvalIcon
            }
            if let summary = item.summary {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button("Keep")   { approval = .approved }.tint(.green).buttonStyle(.bordered).controlSize(.small)
                Button("Reject") { approval = .denied   }.tint(.red  ).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var approvalIcon: some View {
        switch approval {
        case .pending:  Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        case .approved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:   Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// MARK: - Supporting Types

enum ReviewApproval: Equatable { case pending, approved, denied }

struct MacItemSnapshot {
    let title: String?; let summary: String?; let entityType: String?; let url: String?
    let tags: [String]; let transcription: String?; let categories: [String]
    let purposes: [String]; let placeContext: PlaceContext?; let webContext: WebContext?
    let documentContext: DocumentContext?; let qrContext: QRCodeContext?

    init(from item: ProcessedItem) {
        title = item.title; summary = item.summary; entityType = item.entityType; url = item.url
        tags = item.tags; transcription = item.transcription; categories = item.categories
        purposes = item.purposes; placeContext = item.placeContext; webContext = item.webContext
        documentContext = item.documentContext; qrContext = item.qrContext
    }

    func restore(to item: ProcessedItem) {
        item.title = title; item.summary = summary; item.entityType = entityType; item.url = url
        item.tags = tags; item.transcription = transcription; item.categories = categories
        item.purposes = purposes; item.placeContext = placeContext; item.webContext = webContext
        item.documentContext = documentContext; item.qrContext = qrContext
    }
}
