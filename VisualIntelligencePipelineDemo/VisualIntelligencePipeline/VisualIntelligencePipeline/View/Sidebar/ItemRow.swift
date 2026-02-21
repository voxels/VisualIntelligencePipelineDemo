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
                    if let summary = item.summary, !summary.isEmpty {
                        let parsed = parseSummaryModelBadge(from: summary)
                        Text(parsed.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            
                        if let badge = parsed.badge {
                            Text(badge)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    } else {
                        Text(formattedDate)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
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
    
    /// Parses `[Model: ModelName]` from the end of the summary.
    private func parseSummaryModelBadge(from summary: String) -> (text: String, badge: String?) {
        let pattern = #"^\s*(.*?)\s*\[Model:\s*(.*?)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (summary, nil)
        }
        
        let nsString = summary as NSString
        let results = regex.matches(in: summary, range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first, match.numberOfRanges == 3 {
             let cleanedText = nsString.substring(with: match.range(at: 1))
             let modelBadge = nsString.substring(with: match.range(at: 2))
             return (cleanedText, modelBadge)
        }
        
        return (summary, nil)
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        ThumbnailView(item: item, size: 36, cornerRadius: 6)
    }
}
