import SwiftUI
import DiverKit
import AVKit

// MARK: - Layer Components

struct VisualIntelligenceReviewLayer: View {
    @Bindable var viewModel: VisualIntelligenceViewModel
    @State private var currentIndex: Int = 0
    
    var body: some View {
        if let videoURL = viewModel.capturedVideoURL {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let capturedImage = viewModel.capturedImage, viewModel.sessionImages.count == 1 {
            ZStack {
                Image(uiImage: capturedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                Rectangle()
                    .background(.ultraThinMaterial)
                    .overlay(
                        Group {
                            if let sifted = viewModel.siftedImage {
                                SiftedSubjectView(
                                    siftedImage: sifted,
                                    boundingBox: viewModel.siftedBoundingBox,
                                    backingImageSize: viewModel.capturedImage?.size ?? .zero,
                                    peelAmount: $viewModel.peelAmount
                                )
                            }
                        }
                            .allowsHitTesting(false)
                    )
                    .overlay(siftingGestureLayer)
            }
        } else if viewModel.sessionImages.count > 1 {
            // Horizontal carousel for session images
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(Array(viewModel.sessionImages.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: geometry.size.width, height: geometry.size.height - 40)
                                        .clipped()
                                        .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollIndicators(.visible)
                        .scrollPosition(id: Binding(
                            get: { currentIndex },
                            set: { newValue in
                                if let newValue {
                                    currentIndex = newValue
                                    // Sync selected image with carousel position
                                    if newValue < viewModel.sessionImages.count {
                                        viewModel.capturedImage = viewModel.sessionImages[newValue]
                                    }
                                }
                            }
                        ))
                    }
                }
            }
            .background(Color.black)
        } else {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                Text("Loading image...")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Sifting Gesture Layer
    
    @ViewBuilder
    private var siftingGestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let dragAmount = -value.translation.height
                        if dragAmount > 10 {
                            if viewModel.siftedImage == nil && !viewModel.isAnalyzing {
                                if let image = viewModel.capturedImage {
                                    viewModel.analyzeStaticImage(image)
                                }
                            }
                            viewModel.updatePeelAmount(min(1.0, dragAmount / 250.0))
                        }
                    }
                    .onEnded { value in
                        let dragAmount = -value.translation.height
                        if dragAmount > 150 {
                            if let sifted = viewModel.siftedImage {
                                viewModel.saveToPhotoLibrary(image: sifted)
                            }
                        }
                        withAnimation { viewModel.updatePeelAmount(0) }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        if viewModel.siftedImage == nil && !viewModel.isAnalyzing {
                            if let image = viewModel.capturedImage {
                                viewModel.analyzeStaticImage(image)
                            }
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.updatePeelAmount(0.15)
                        }
                    }
            )
    }
}

struct VisualIntelligenceCameraLayer: View {
    var viewModel: VisualIntelligenceViewModel
    
    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.cameraManager.session)
                .ignoresSafeArea()
            
            // SAM 2.1 Pixel-Perfect Structural Mask Overlay
            if let mask = viewModel.cameraManager.currentSegmentationMask {
                Image(decorative: mask, scale: 1.0)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fill) // Matches the camera preview scale
                    .foregroundStyle(.yellow.opacity(0.35)) // Target-locked UI style
                    .ignoresSafeArea()
                    .transition(AnyTransition.opacity.animation(.easeInOut(duration: 0.15)))
                    .allowsHitTesting(false) // Let touches pass through to shutters/gestures
            }
        }
        .animation(.default, value: viewModel.cameraManager.currentSegmentationMask != nil)
    }
}
