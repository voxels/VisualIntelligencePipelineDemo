//
//  ItemRowWithActions.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — item row with swipe and context menu actions.
//

import SwiftUI
import DiverKit

struct ItemRowWithActions: View {
    let item: ProcessedItem
    let onDelete: () -> Void
    let onReprocess: () -> Void
    
    var body: some View {
        ItemRow(item: item)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    onReprocess()
                } label: {
                    Label("Reprocess", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button {
                    onReprocess()
                } label: {
                    Label("Reprocess Item", systemImage: "arrow.clockwise")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            }
    }
}
