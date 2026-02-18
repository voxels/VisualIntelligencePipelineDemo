//
//  SessionRowLabel.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — session row with hero image or fallback icon.
//

import SwiftUI
import DiverKit

#if os(iOS)
import UIKit
#endif

struct SessionRowLabel: View {
    let session: SessionMetadata
    let allItems: [ProcessedItem]
    
    private var sessionTitle: String {
        if let title = session.title, !title.isEmpty {
            return title
        }
        
        // Try to use a top concept from session items as fallback
        let topConcept = sessionItems
            .flatMap { $0.categories + $0.tags }
            .reduce(into: [:]) { counts, concept in counts[concept, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key
        
        if let concept = topConcept, !concept.isEmpty {
            return concept.capitalized
        }
        
        if let location = session.locationName, !location.isEmpty {
            return location
        }
        return "Session"
    }
    
    private var subtitle: String {
        var components: [String] = []
        if let loc = session.locationName, !loc.isEmpty, session.title != nil {
            // Only show location in subtitle if we have a title (otherwise it's the title)
            components.append(loc)
        }
        
        // Add dominant activity/purpose if available
        let purposes = sessionItems.flatMap { $0.purposes }.filter { !$0.isEmpty }
        if let topPurpose = purposes.reduce(into: [:], { counts, purpose in counts[purpose, default: 0] += 1 })
            .max(by: { $0.value < $1.value })?.key {
            components.append(topPurpose)
        }
        
        components.append(session.createdAt.formatted(date: .abbreviated, time: .shortened))
        return components.joined(separator: " • ")
    }
    
    private var sessionItems: [ProcessedItem] {
        allItems.filter { $0.sessionID == session.sessionID && $0.status == .ready }
    }
    
    private var heroImage: UIImage? {
        for item in sessionItems {
            if let data = item.rawPayload, let image = UIImage(data: data) {
                return image
            }
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
    
    private var fallbackConfig: ItemIconConfig {
        // Check for dominant purpose to determine icon (e.g. Activity)
        let purposes = sessionItems.flatMap { $0.purposes }
        if !purposes.isEmpty {
            return ItemIconConfig(iconName: "figure.run", color: .orange)
        }
        
        if let first = sessionItems.first {
            return ItemIconConfig.forItem(first)
        }
        return ItemIconConfig(iconName: "photo.stack", color: .secondary)
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Hero Image with overlay text
            if let image = heroImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(minWidth: 0, maxWidth: 280, minHeight: 0, maxHeight: 280)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sessionTitle)
                                .font(.headline)
                                .bold()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(8)
                    }
                    .cornerRadius(8)
            } else {
                // Fallback: Icon + Text layout
                HStack(spacing: 10) {
                    let config = fallbackConfig
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(config.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: config.iconName)
                                .foregroundStyle(config.color)
                                .font(.title3)
                        }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionTitle)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            
            // LLM Session Summary
            if ContextQuestionService.isAvailable, let summary = session.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
            } else if ContextQuestionService.isAvailable {
                Text("No Summary Available")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.top, 4)
            }
        }
        .padding(4)
    }
}
