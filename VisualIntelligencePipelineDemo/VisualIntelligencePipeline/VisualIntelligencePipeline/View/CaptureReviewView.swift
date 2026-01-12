import SwiftUI
import DiverKit
import DiverShared

struct CaptureReviewView: View {
    let image: UIImage
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    
    @State private var showingShareSheet = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
                .overlay(
                    // Dim background as we peel
                    Color.black.opacity(0.6 * viewModel.peelAmount)
                        .ignoresSafeArea()
                )
                .overlay(
                    // Sifted Overlay on top of static image
                    Group {
                        if let sifted = viewModel.siftedImage {
                            SiftedSubjectView(
                                siftedImage: sifted,
                                boundingBox: viewModel.siftedBoundingBox,
                                peelAmount: $viewModel.peelAmount
                            )
                        }
                    }
                )
            
            // Interaction Layer (Deferred Sifting)
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Vertical drag controls Peel Effect
                                let dragAmount = -value.translation.height
                                if dragAmount > 10 {
                                    // Trigger analysis if not already done
                                    if viewModel.siftedImage == nil && !viewModel.isAnalyzing {
                                        viewModel.analyzeStaticImage(image)
                                    }
                                    
                                    viewModel.updatePeelAmount(min(1.0, dragAmount / 250.0))
                                }
                            }
                            .onEnded { value in
                                let dragAmount = -value.translation.height
                                if dragAmount > 150 {
                                    // Sift Complete -> Save Sifted
                                    if let sifted = viewModel.siftedImage {
                                        viewModel.saveToPhotoLibrary(image: sifted)
                                    }
                                    withAnimation { viewModel.updatePeelAmount(0) }
                                } else {
                                    withAnimation { viewModel.updatePeelAmount(0) }
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .onEnded { _ in
                                // Trigger sifting analysis on long press
                                if viewModel.siftedImage == nil && !viewModel.isAnalyzing {
                                    viewModel.analyzeStaticImage(image)
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.updatePeelAmount(0.15) // Initial "sticker" pop
                                }
                            }
                    )
            }
            
            // Premium Action Cluster (Floating Pill)
            VStack {
                Spacer()
                
                // Metadata Overlay (Tags, Text, etc.)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.results, id: \.title) { result in
                            // Filter out raw sifting result from this list as it has its own visual
                            if case .siftedSubject(_, _) = result { EmptyView() }
                            else {
                                HStack(spacing: 8) {
                                    Image(systemName: result.icon)
                                        .font(.caption)
                                    Text(result.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
                
                HStack(spacing: 0) {
                    // Re-take Button
                    Button {
                        hapticFeedback(.soft)
                        viewModel.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 64)
                    }
                    
                    Divider()
                        .frame(height: 30)
                        .background(.white.opacity(0.3))
                    
                    // Primary Save -> Diver
                    Button {
                        hapticFeedback(.heavy)
                        viewModel.commitReviewSave()
                        // Close after a brief success delay/feedback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            viewModel.reset()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 24))
                            Text("Save to Diver")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .frame(height: 64)
                        .background(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                .opacity(0.8)
                        )
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .padding(.bottom, 40)
            }
            .zIndex(30)
        }
    }
    
    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
