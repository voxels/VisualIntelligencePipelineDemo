//
//  AppleMusicReferenceView.swift
//  VisualIntelligencePipeline
//
//  Created by Antigravity on 01/11/26.
//

import SwiftUI
import DiverShared
import DiverKit

struct AppleMusicReferenceView: View {
    let item: ProcessedItem
    
    // We expect webContext.structuredData or just webContext fields to hold MusicKit info
    // But since AppleMusicEnrichmentService populated `item` fields directly, we can use them.
    // Specifically `webContext.snapshotURL` for deep links or item.url
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                if let coverUrl = item.webContext?.snapshotURL ?? item.url, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            fallbackCover
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(6)
                    .shadow(radius: 4)
                } else {
                    fallbackCover
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Unknown Title")
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    if let subtitle = item.summary {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack {
                        Image(systemName: "apple.logo")
                            .font(.caption2)
                        Text("Apple Music")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.pink)
                    .padding(.top, 2)
                }
                Spacer()
            }
            
            // Actions
            if let webURL = item.resolvedWebURL {
                Link(destination: webURL) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play on Apple Music")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.pink.opacity(0.1))
                    .foregroundColor(.pink)
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var fallbackCover: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundColor(.pink.opacity(0.5))
        }
        .frame(width: 80, height: 80)
        .cornerRadius(6)
    }
}
