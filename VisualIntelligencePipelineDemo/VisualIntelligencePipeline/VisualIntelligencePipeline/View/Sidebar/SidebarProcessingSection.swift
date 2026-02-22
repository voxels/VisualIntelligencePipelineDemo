import SwiftUI
import SwiftData
import DiverKit

/// Owns its own `@Query` for processing items — changes to processing state
/// only re-render this section, not the entire sidebar.
struct SidebarProcessingSection: View {
    @Query(filter: #Predicate<ProcessedItem> { $0.statusRaw == "queued" || $0.statusRaw == "processing" }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var processingItems: [ProcessedItem]
    
    @State private var processingExpanded = true
    @Environment(\.modelContext) private var modelContext
    var viewModel: SidebarViewModel
    
    var body: some View {
        if !processingItems.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $processingExpanded) {
                    ForEach(processingItems) { item in
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? item.displayLabel)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                
                                if let lastLog = item.processingLog.last {
                                    let message = lastLog.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
                                    Text(message.isEmpty ? item.status.rawValue.capitalized : message)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text(item.status.rawValue.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                viewModel.processNow(item)
                            } label: {
                                Label("Process Now", systemImage: "bolt.fill")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.cancelProcessing(item, context: modelContext)
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                        }
                    }
                } label: {
                    Label("Processing (\(processingItems.count))", systemImage: "gear")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
