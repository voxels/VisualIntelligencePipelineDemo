//
//  QueueProgressView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import DiverKit

/// Compact bottom toast showing queue processing progress.
public struct QueueProgressView: View {
    public let totalCount: Int
    public let completedCount: Int
    public let currentItemTitle: String?
    public let statusMessage: String?
    public let progress: Double

    public init(totalCount: Int, completedCount: Int, currentItemTitle: String?,
                statusMessage: String?, progress: Double) {
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.currentItemTitle = currentItemTitle
        self.statusMessage = statusMessage
        self.progress = progress
    }

    public var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(progressTint)
            HStack(spacing: 8) {
                if completedCount < totalCount {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerText).font(.caption).fontWeight(.semibold).foregroundStyle(.primary)
                    if completedCount < totalCount {
                        if let status = statusMessage {
                            Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let title = currentItemTitle {
                            Text(title).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Text("\(completedCount)/\(totalCount)")
                    .font(.caption).fontWeight(.medium).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var headerText: String {
        completedCount >= totalCount ? "Processing Complete" : "Processing Items…"
    }
    private var progressTint: Color {
        completedCount >= totalCount ? .green : .accentColor
    }
}
