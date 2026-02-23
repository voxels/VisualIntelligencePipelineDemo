//
//  SessionRowLabel.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — session row with hero image or fallback icon.
//

import SwiftUI
import DiverKit
import SwiftData

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
    
    @State private var heroImage: UIImage? = nil
    @Environment(\.modelContext) private var modelContext
    
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
    
    // Core function to fetch thumbnail without blocking main thread
    private func loadHeroImage() async {
        // 1. Check shared fast memory cache first
        if let cached = ThumbnailCache.shared.image(forKey: session.sessionID) {
            await MainActor.run { self.heroImage = cached }
            return
        }
        
        let itemIDs = sessionItems.map { $0.persistentModelID }
        guard !itemIDs.isEmpty else { return }
        
        // Pass container to detached task to safely read external storage
        let container = modelContext.container
        
        let loadedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            
            for id in itemIDs {
                guard let item = bgContext.model(for: id) as? ProcessedItem else { continue }
                if let data = item.rawPayload {
                    if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                        let options = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 300,
                            kCGImageSourceCreateThumbnailWithTransform: true
                        ] as CFDictionary
                        if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) {
                            return UIImage(cgImage: cgImage)
                        }
                    }
                    if let image = UIImage(data: data) { return image }
                }
                if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                    return image
                }
            }
            return nil
        }.value
        
        if let img = loadedImage {
            // Store back to cache for instantaneous sibling redraws
            ThumbnailCache.shared.insert(img, forKey: session.sessionID)
            await MainActor.run { self.heroImage = img }
        }
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
                // Parse out [Model: XYZ] strings into a badge
                let parsed = parseSummaryModelBadge(from: summary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(parsed.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        
                    if let badge = parsed.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(badge.contains("Edge") ? Color.purple.opacity(0.15) : Color.blue.opacity(0.1))
                            )
                            .foregroundStyle(badge.contains("Edge") ? .purple : .blue)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if ContextQuestionService.isAvailable {
                Text("No Summary Available")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.top, 4)
            }
        }
        .padding(4)
        .task {
            // Load thumbnail async when view appears to prevent UI hang
            if heroImage == nil {
                await loadHeroImage()
            }
        }
    }
    
    /// Parses `[Model: ModelName]` from the end of the summary.
    private func parseSummaryModelBadge(from summary: String) -> (text: String, badge: String?) {
        let pattern = #"\s*\[Model:\s*(.*?)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (summary, nil)
        }
        
        let range = NSRange(summary.startIndex..<summary.endIndex, in: summary)
        if let match = regex.firstMatch(in: summary, options: [], range: range) {
            let badgeRange = Range(match.range(at: 1), in: summary)!
            let fullMatchRange = Range(match.range, in: summary)!
            
            let badgeText = String(summary[badgeRange])
            let cleanText = summary.replacingCharacters(in: fullMatchRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            return (cleanText, badgeText)
        }
        
        return (summary, nil)
    }
}
