//
//  SessionCardView.swift
//  Diver
//
//  Created by Antigravity on 01/11/26.
//

import SwiftUI
import SwiftData
import DiverKit

struct SessionCardView: View {
    let sessionID: String
    let items: [ProcessedItem]
    let metadata: DiverSession?
    @Binding var isExpanded: Bool
    
    let isSelectionMode: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    
    // Derived properties
    private var heroImage: UIImage? {
        // Find best quality image (e.g. from rawPayload or web snapshot)
        // Prefer first item in list for consistency
        for item in items {
            if let data = item.rawPayload, let image = UIImage(data: data) {
                return image
            }
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
    
    private var title: String {
        metadata?.title ?? items.first?.title ?? "Untitled Session"
    }
    
    private var subtitle: String {
        // Location + Date or just Date
        var components: [String] = []
        if let loc = metadata?.locationName {
            components.append(loc)
        }
        if let date = items.first?.createdAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            components.append(formatter.string(from: date))
        }
        return components.isEmpty ? "Unknown Date" : components.joined(separator: " • ")
    }
    
    private var summary: String? {
        metadata?.summary
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button {
                    onSelect()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? .blue : .secondary)
                }
                .padding(.leading, 8)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                // Hero Image Area
                if let image = heroImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.title3)
                                    .bold()
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .padding()
                        }
                } else {
                    // Fallback Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                }
                
                // Tertiary Context / LLM Summary
                if let summary = summary {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session Summary")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Text(summary)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineSpacing(2)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, isExpanded ? 8 : 12)
                    .padding(.top, 8)
                }
                
                // Dropdown Chevron Area (Tap to expand)
                HStack {
                    Text(isExpanded ? "Hide items" : "Show \(items.count) items")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.blue)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .opacity(isSelectionMode ? 0 : 1) // Hide chevron in edit mode
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemBackground))
                .contentShape(Rectangle()) // Hit test helper for chevron area
                 
                // Divider if not expanded, or if expanded content follows in SidebarView
                 if !isExpanded {
                     Divider()
                 }
            }
            .contentShape(Rectangle()) // Make entire card area tappable
            .onTapGesture {
                if isSelectionMode {
                    onSelect()
                } else {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.trailing, 4) 
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle()) // Make full width tappable
        .onTapGesture {
            if isSelectionMode {
                onSelect()
            }
        }
    }
}
