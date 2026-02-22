import SwiftUI
import SwiftData
import DiverKit
#if os(iOS)
import UIKit
#endif

/// Owns its own `@Query` for sessions — session summary changes
/// only re-render this section, not the entire sidebar.
struct SidebarIntelligenceSection: View {
    @Query(sort: \SessionMetadata.updatedAt, order: .reverse)
    private var sessions: [SessionMetadata]
    
    // readyItems needed for previewImage lookup
    @Query(filter: #Predicate<ProcessedItem> { $0.statusRaw != "queued" && $0.statusRaw != "processing" && $0.statusRaw != "failed" }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var readyItems: [ProcessedItem]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationManager: NavigationManager
    var viewModel: SidebarViewModel
    var cachedRelatedConcepts: [UserConcept]
    
    var body: some View {
        Section("Current Context") {
            if let lastSession = sessions.first {
                // Full contextual summary
                if ContextQuestionService.isAvailable, let summary = lastSession.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                
                // Related concepts chips
                if ContextQuestionService.isAvailable, !cachedRelatedConcepts.isEmpty {
                    let concepts = cachedRelatedConcepts
                    if !concepts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(concepts) { concept in
                                    Text(concept.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(.purple.opacity(0.1))
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(.purple.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Button {
                    navigationManager.scanSessionID = lastSession.sessionID
                    navigationManager.isScanActive = true
                } label: {
                    HStack(spacing: 12) {
                        // Thumbnail Preview
                        if let preview = previewImage(for: lastSession) {
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            Image(systemName: "plus.viewfinder")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(.cyan.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Image")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            
                            if let location = lastSession.locationName {
                                Text(location)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(lastSession.title ?? "Current Session")
                                    .font(.caption2)
                                .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        viewModel.importTargetSession = lastSession
                        viewModel.isImporting = true
                    } label: {
                        Label("Import from Photos", systemImage: "photo")
                    }
                }
                
                // New Note button
                Button {
                    let newNote = viewModel.createNewNoteForSession(lastSession, context: modelContext)
                    navigationManager.selectedSession = lastSession
                    navigationManager.selection = newNote
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.purple)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Note")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            
                            Text("Add text to context")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    navigationManager.scanSessionID = nil
                    navigationManager.isScanActive = true
                } label: {
                    Label("Scan for Context", systemImage: "sparkles.tv")
                        .foregroundStyle(.cyan)
                }
            }
        }
    }
    
    private func previewImage(for session: SessionMetadata) -> UIImage? {
        viewModel.previewImage(for: session, allItems: readyItems)
    }
}
