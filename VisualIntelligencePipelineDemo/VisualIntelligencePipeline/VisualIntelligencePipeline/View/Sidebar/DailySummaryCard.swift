//
//  DailySummaryCard.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — daily focus summary card.
//

import SwiftUI
import DiverKit

struct DailySummaryCard: View {
    var service: DailyContextService
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S FOCUS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                if service.isGenerating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Updating summary...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(service.dailySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Label("Your Day", systemImage: "sun.max.fill")
                    .foregroundStyle(.orange)
                Spacer()
                if service.hasContent {
                    Button {
                        Task { await service.updateSummary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
