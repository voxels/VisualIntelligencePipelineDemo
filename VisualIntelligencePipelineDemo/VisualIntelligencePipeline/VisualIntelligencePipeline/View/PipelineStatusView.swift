import SwiftUI
import DiverKit

struct PipelineStatusView: View {
    let status: VisualIntelligenceViewModel.PipelineStatus
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon Stack
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                if status == .complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(statusColor)
                } else {
                    ProgressView()
                        .tint(statusColor)
                        .scaleEffect(0.8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(status.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                // Progress Bar logic could go here
                Text(stepDescription)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 260)
    }
    
    private var statusColor: Color {
        switch status {
        case .sifting, .capturing: return .blue
        case .reading: return .purple
        case .enriching: return .orange
        case .reasoning: return .pink
        case .complete: return .green
        case .idle: return .gray
        }
    }
    
    private var stepDescription: String {
        switch status {
        case .capturing: return "Processing full resolution frame"
        case .sifting: return "Separating subject from background"
        case .reading: return "Extracting text and structure"
        case .enriching: return "Querying maps and sensors"
        case .reasoning: return "Generating contextual insights"
        case .complete: return "Ready for review"
        case .idle: return "Waiting for capture"
        }
    }
}
