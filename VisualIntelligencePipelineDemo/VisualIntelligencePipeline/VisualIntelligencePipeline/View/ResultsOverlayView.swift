import SwiftUI
import DiverKit

struct ResultsOverlayView: View {
    let results: [IntelligenceResult]
    let onSelect: (IntelligenceResult) -> Void
    
    // Derived collections
    private var visualResults: [IntelligenceResult] {
        results.filter {
            if case .siftedSubject = $0 { return true }
            if case .text = $0 { return true }
            if case .product = $0 { return true }
            if case .document = $0 { return true }
            return false
        }
    }
    
    private var contextResults: [IntelligenceResult] {
        results.filter {
            if case .semantic = $0 { return true }
            if case .purpose = $0 { return true }
            if case .entertainment = $0 { return true }
            return false
        }
    }
    
    private var actionResults: [IntelligenceResult] {
        results.filter {
            if case .qr = $0 { return true }
            if case .richWeb = $0 { return true }
            return false
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Group 1: Visuals (Blue)
                if !visualResults.isEmpty {
                    ResultGroup(title: "Visuals", color: .blue, results: visualResults, onSelect: onSelect)
                }
                
                // Group 2: Context (Purple)
                if !contextResults.isEmpty {
                    ResultGroup(title: "Context", color: .purple, results: contextResults, onSelect: onSelect)
                }
                
                // Group 3: Actions (Green)
                if !actionResults.isEmpty {
                    ResultGroup(title: "Actions", color: .green, results: actionResults, onSelect: onSelect)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct ResultGroup: View {
    let title: String
    let color: Color
    let results: [IntelligenceResult]
    let onSelect: (IntelligenceResult) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(color)
                .rotationEffect(.degrees(-90))
                .fixedSize()
            
            ForEach(results, id: \.self) { result in
                Button {
                    onSelect(result)
                } label: {
                    ResultPill(result: result, color: color)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.1))
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct ResultPill: View {
    let result: IntelligenceResult
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.icon)
            if !result.subtitle.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title).font(.caption.bold())
                    Text(result.subtitle).font(.caption2).opacity(0.7)
                }
            } else {
                Text(result.title).font(.caption.bold())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .foregroundStyle(.white)
    }
}
