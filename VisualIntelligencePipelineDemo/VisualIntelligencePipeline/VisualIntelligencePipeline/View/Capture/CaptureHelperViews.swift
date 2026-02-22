import SwiftUI
import DiverKit
#if os(iOS)
import UIKit
#endif

// MARK: - Consolidated Dependencies

struct SessionLocationBar: View {
    var viewModel: VisualIntelligenceViewModel
    
    var body: some View {
        HStack {
            // Location Info (Tap to Edit)
            Button {
                viewModel.showingPlaceSelection = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(viewModel.isLocationPinned ? .yellow : .blue)
                    
                    if let place = viewModel.selectedPlace {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title ?? "Unknown Location")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            
                            if let addr = place.placeContext?.address {
                                Text(addr)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    } else if viewModel.pipelineStatus == .enriching {
                        Text("Locating...")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    } else {
                        Text("Add Location")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }
            }
            
            Spacer()
            
            // Pin Toggle
            if viewModel.selectedPlace != nil {
                Button {
                    withAnimation {
                        viewModel.isLocationPinned.toggle()
                    }
                    // Feedbac
#if os(iOS)
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = viewModel.isLocationPinned ? .heavy : .light
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
                } label: {
                    Image(systemName: viewModel.isLocationPinned ? "pin.fill" : "pin")
                        .font(.body)
                        .foregroundStyle(viewModel.isLocationPinned ? .yellow : .white.opacity(0.5))
                        .padding(8)
                }
                .glassCapsule()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.horizontal)
    }
}

struct ResultsOverlayView: View {
    let results: [IntelligenceResult]
    let onSelect: (IntelligenceResult) -> Void
    
    // Derived collections
    private var visualResults: [IntelligenceResult] {
        results.filter {
            if case .siftedSubject = $0 { return true }
            if case .text = $0 { return true }
            if case .product = $0 { return true }
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
        // Documents first, then QR codes and web links
        let documents = results.filter { if case .document = $0 { return true }; return false }
        let others = results.filter {
            if case .qr = $0 { return true }
            if case .richWeb = $0 { return true }
            return false
        }
        return documents + others
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Group 1: Actions (Green) - Show first for quick access
                if !actionResults.isEmpty {
                    ResultGroup(title: "Actions", color: .green, results: actionResults, onSelect: onSelect)
                }
                
                // Group 2: Visuals (Blue)
                if !visualResults.isEmpty {
                    ResultGroup(title: "Visuals", color: .blue, results: visualResults, onSelect: onSelect)
                }
                
                // Note: Context results are now shown in ContextChipBar below
            }
            .padding(.horizontal)
        }
    }
}

struct ResultGroup: View {
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

struct ResultPill: View {
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
        .glassEffect()
        .clipShape(Capsule())
        .foregroundStyle(.white)
    }
}

struct ContextChipBar: View {
    var viewModel: VisualIntelligenceViewModel
    @Binding var isEnteringCustomContext: Bool
    
    // Context results from intelligence pipeline (semantic, purpose, entertainment)
    private var contextResults: [IntelligenceResult] {
        viewModel.results.filter {
            if case .semantic = $0 { return true }
            if case .purpose = $0 { return true }
            if case .entertainment = $0 { return true }
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Header
            HStack {
                Text("Context")
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 1. Primary Action: Add Custom Context
                    Button {
                        isEnteringCustomContext = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Add Custom")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    
                    // 2. Selected Contexts (Persisted/Active)
                    ForEach(Array(viewModel.selectedPurposes).sorted(), id: \.self) { context in
                        Button {
                            toggleContext(context)
                        } label: {
                            HStack(spacing: 4) {
                                Text(context)
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect()
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                            .foregroundStyle(.white)
                        }
                    }
                    
                    // 3. Suggestions (from AI) - Only show if not selected
                    if let purposeResult = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
                       case .purpose(let statements) = purposeResult {
                        
                        ForEach(statements, id: \.self) { statement in
                            if !viewModel.selectedPurposes.contains(statement) {
                                Button {
                                    toggleContext(statement)
                                } label: {
                                    Text(statement)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .glassEffect()
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    
                    // 4. Context Results (semantic, entertainment) - Purple accent
                    ForEach(contextResults, id: \.self) { result in
                        ContextResultPill(result: result)
                            .onTapGesture {
                                toggleContext(result.title)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private struct ContextResultPill: View {
        let result: IntelligenceResult
        
        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: result.icon)
                    .font(.caption)
                Text(result.title)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.purple.opacity(0.3))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.purple.opacity(0.5), lineWidth: 1)
            )
            .foregroundStyle(.white)
        }
    }
    
    private func toggleContext(_ text: String) {
        withAnimation {
            if viewModel.selectedPurposes.contains(text) {
                viewModel.selectedPurposes.remove(text)
                if viewModel.sessionTitle == text { viewModel.sessionTitle = nil }
            } else {
                viewModel.selectedPurposes.insert(text)
                viewModel.sessionTitle = text
                viewModel.refineContext(with: text)
            }
        }
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }
}
