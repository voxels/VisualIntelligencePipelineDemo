import SwiftUI
import DiverKit

/// Compact bottom toast showing queue processing progress.
/// Appears whenever the MetadataPipelineService is processing imports or shared links.
struct QueueProgressView: View {
    let totalCount: Int
    let completedCount: Int
    let currentItemTitle: String?
    let statusMessage: String?
    let progress: Double
    
    var body: some View {
        VStack(spacing: 6) {
            // Progress bar
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(progressTint)
            
            HStack(spacing: 8) {
                // Spinner or checkmark
                if completedCount < totalCount {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    if completedCount < totalCount {
                        if let status = statusMessage {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let title = currentItemTitle {
                            Text(title)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                Text("\(completedCount)/\(totalCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
        if completedCount >= totalCount {
            return "Processing Complete"
        }
        return "Processing Items…"
    }
    
    private var progressTint: Color {
        completedCount >= totalCount ? .green : .accentColor
    }
}
