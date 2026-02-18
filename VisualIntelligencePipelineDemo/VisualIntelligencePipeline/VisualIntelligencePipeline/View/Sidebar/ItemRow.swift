//
//  ItemRow.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — individual item row display.
//

import SwiftUI
import DiverKit

struct ItemRow: View {
    let item: ProcessedItem
    
    private var displayTitle: String {
        item.displayTitle
    }
    
    private var formattedDate: String {
        item.relativeUpdatedDate
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                if let location = item.placeContext?.name, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(formattedDate)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        ThumbnailView(item: item, size: 36, cornerRadius: 6)
    }
}
