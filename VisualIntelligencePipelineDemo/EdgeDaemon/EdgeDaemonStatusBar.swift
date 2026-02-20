//
//  EdgeDaemonStatusBar.swift
//  EdgeDaemon
//
//  SF Symbol status indicator showing daemon state via color and animation.
//

import SwiftUI

/// Status indicator showing daemon state.
struct EdgeDaemonStatusBar: View {
    let status: DaemonStatus
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: status == .processing)
                .symbolEffect(.variableColor, isActive: status == .starting)
            
            Text(status.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.1), in: Capsule())
    }
    
    private var statusIcon: String {
        switch status {
        case .idle: return "circle"
        case .starting: return "circle.dashed"
        case .listening: return "antenna.radiowaves.left.and.right"
        case .processing: return "bolt.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .starting: return .orange
        case .listening: return .green
        case .processing: return .blue
        case .error: return .red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        EdgeDaemonStatusBar(status: .idle)
        EdgeDaemonStatusBar(status: .starting)
        EdgeDaemonStatusBar(status: .listening)
        EdgeDaemonStatusBar(status: .processing)
        EdgeDaemonStatusBar(status: .error)
    }
    .padding()
}
