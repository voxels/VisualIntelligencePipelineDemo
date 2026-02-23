import SwiftUI
import SwiftData
import DiverKit
import SharedWithYou

public struct CommonFooterView: View {
    let item: ProcessedItem
    @StateObject private var viewModel = ReferenceDetailViewModel()
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // 1. Shared with You Attribution
            if let attributionID = item.attributionID,
               let highlight = sharedWithYouManager.findHighlight(id: attributionID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared with You")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    AttributionViewWrapper(highlight: highlight)
                        .frame(height: 50)
                }
                .detailCardStyle()
            }
            
            // 2. Semantic Tags Section
            let semanticTags = Array(Set(item.visualTags + item.tags + item.categories + item.purposes)).sorted()
            if !semanticTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Semantic Tags")
                        .font(.title3)
                        .bold()
                    
                    FlowLayout(spacing: 8) {
                        ForEach(semanticTags, id: \.self) { tag in
                            Button {
                                if let sessionID = item.sessionID, let context = item.modelContext {
                                    let descriptor = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sessionID })
                                    if let session = try? context.fetch(descriptor).first {
                                        session.title = tag.capitalized
                                        session.updatedAt = Date()
                                    } else {
                                        let newSession = SessionMetadata(sessionID: sessionID, title: tag.capitalized)
                                        context.insert(newSession)
                                    }
                                    Task { @MainActor in try? context.save() }
                                    
                                    // Feedback
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                }
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .glass(cornerRadius: 8)
                                    .foregroundStyle(.blue)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.removeSemanticTag(tag, from: item)
                                } label: {
                                    Label("Delete Tag", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .detailCardStyle()
            }
            
            // 3. AI Identified Purposes & Intent
            if let fastVLM = item.fastVLMAnalysis {
                VStack(alignment: .leading, spacing: 12) {
                    Label("AI Intent Recognition", systemImage: "apple.intelligence")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    if let purpose = fastVLM.suggestedPurpose {
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(purpose)
                                .font(.subheadline)
                        }
                    }
                }
                .detailCardStyle()
            }
            
            // 4. Capture Siblings
            if let masterID = item.masterCaptureID {
                CaptureSiblingsView(masterID: masterID, currentID: item.id)
                    .padding(.bottom, 12)
                    .detailCardStyle()
            }
            
            // 5. References
            if let refs = item.childItems, !refs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("References")
                        .font(.title2)
                        .bold()
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                        ForEach(refs) { ref in
                            ReferenceCardWrapper(item: ref)
                        }
                    }
                    .padding(.horizontal)
                }
                .detailCardStyle()
            }
            
            // 6. Dates and EXIF Metadata
            VStack(alignment: .leading, spacing: 8) {
                Text("Metadata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text("Captured")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.createdAt, style: .date)
                    Text(item.createdAt, style: .time)
                }
                
                if item.updatedAt != item.createdAt {
                    HStack {
                        Text("Modified")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.updatedAt, style: .date)
                        Text(item.updatedAt, style: .time)
                    }
                }

                
                if let type = item.mediaType {
                    HStack {
                        Text("Media Type")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(type.uppercased())
                    }
                }
            }
            .font(.caption2)
            .padding()
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }
}
