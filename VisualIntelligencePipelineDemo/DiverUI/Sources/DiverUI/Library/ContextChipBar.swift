//
//  ContextChipBar.swift
//  DiverUI — cross-platform
//
//  Already had #if os(iOS) guard on UIImpactFeedbackGenerator — kept.
//

import SwiftUI
import DiverKit

public struct ContextChipBar: View {
    public var viewModel: VisualIntelligenceViewModel
    @Binding public var isEnteringCustomContext: Bool

    public init(viewModel: VisualIntelligenceViewModel, isEnteringCustomContext: Binding<Bool>) {
        self.viewModel = viewModel
        self._isEnteringCustomContext = isEnteringCustomContext
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Describe Context")
                    .font(.caption).fontWeight(.bold).textCase(.uppercase).foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Custom
                    Button { isEnteringCustomContext = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                            Text("Add Custom").fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.blue).clipShape(Capsule()).foregroundStyle(.white)
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    }

                    // Selected contexts
                    ForEach(Array(viewModel.selectedPurposes).sorted(), id: \.self) { context in
                        Button { toggleContext(context) } label: {
                            HStack(spacing: 4) {
                                Text(context)
                                Image(systemName: "checkmark").font(.caption.bold())
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.ultraThinMaterial).clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue, lineWidth: 2))
                            .foregroundStyle(.white)
                        }
                    }

                    // AI suggestions
                    if let r = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
                       case .purpose(let statements) = r {
                        ForEach(statements, id: \.self) { statement in
                            if !viewModel.selectedPurposes.contains(statement) {
                                Button { toggleContext(statement) } label: {
                                    Text(statement)
                                        .padding(.horizontal, 16).padding(.vertical, 12)
                                        .background(.ultraThinMaterial).clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
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
