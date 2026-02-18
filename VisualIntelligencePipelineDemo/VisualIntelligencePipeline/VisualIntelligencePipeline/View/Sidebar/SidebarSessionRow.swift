//
//  SidebarSessionRow.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — session row with selection, context menu,
//  swipe actions, drag-and-drop.
//

import SwiftUI
import DiverKit

struct SidebarSessionRow: View {
    let session: SessionMetadata
    @ObservedObject var viewModel: SidebarViewModel
    let allItems: [ProcessedItem]
    let allConcepts: [UserConcept]
    
    let onLocationEdit: (SessionMetadata) -> Void
    let onRename: (SessionMetadata, String) -> Void
    let onNewCollection: (SessionMetadata, String) -> Void
    let onAddSession: (SessionMetadata, SessionCollection) -> Void
    let collections: [SessionCollection]
    let analyzeSession: (SessionMetadata) -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        if viewModel.isSelectionMode {
            selectionRow
                .contextMenu {
                    contextMenuContent
                }
        } else {
            NavigationLink(value: session) {
                SessionRowLabel(session: session, allItems: allItems)
            }
            .contextMenu {
                contextMenuContent
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    viewModel.deleteSession(session, context: modelContext)
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
                
                Button {
                    onRename(session, session.displayTitle)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    viewModel.setSessionAsCurrent(session, context: modelContext)
                } label: {
                    Label("Set Current", systemImage: "clock.arrow.2.circlepath")
                }
                .tint(.orange)
            }
            .draggable(SessionTransfer(id: session.sessionID))
            .dropDestination(for: ItemTransfer.self) { items, location in
                // Allow dropping items into sessions inside collections
                viewModel.moveItems(items, to: session, context: modelContext)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
    }
    
    @State private var isTargeted = false
    
    private var selectionRow: some View {
        Button {
            if viewModel.selectedSessions.contains(session.sessionID) {
                viewModel.selectedSessions.remove(session.sessionID)
            } else {
                viewModel.selectedSessions.insert(session.sessionID)
            }
        } label: {
            HStack {
                Image(systemName: viewModel.selectedSessions.contains(session.sessionID) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedSessions.contains(session.sessionID) ? .blue : .secondary)
                SessionRowLabel(session: session, allItems: allItems)
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // Set as Current (Priority Action)
        Button {
            viewModel.setSessionAsCurrent(session, context: modelContext)
        } label: {
            Label("Set as Current", systemImage: "clock.arrow.2.circlepath")
        }
        
        Divider()
        
        // Add to existing collection
        if !collections.isEmpty {
            Menu {
                ForEach(collections) { collection in
                    Button {
                        onAddSession(session, collection)
                    } label: {
                        Label(collection.name, systemImage: "folder.fill")
                    }
                }
            } label: {
                Label("Add to Collection", systemImage: "folder.badge.plus")
            }
        }
        
        // Create new collection from session
        Button {
            onNewCollection(session, session.displayTitle)
        } label: {
            Label("Create New Collection", systemImage: "folder.fill.badge.plus")
        }
        
        Button {
            // Set target session and open picker
            viewModel.importTargetSession = session
            viewModel.isImporting = true
        } label: {
            Label("Import Photos to Session", systemImage: "photo.badge.plus")
        }
        
        Button {
            onLocationEdit(session)
        } label: {
            Label("Edit Location", systemImage: "mappin.and.ellipse")
        }
        
        Button {
            onRename(session, session.displayTitle)
        } label: {
            Label("Rename Session", systemImage: "pencil")
        }
        
        Button {
            analyzeSession(session)
        } label: {
            Label("Analyze Session", systemImage: "sparkles")
        }
        
        Divider()
        
        Button(role: .destructive) {
            viewModel.deleteSession(session, context: modelContext)
        } label: {
            Label("Delete Session", systemImage: "trash")
        }
    }
}
