import SwiftUI
import DiverKit
import PhotosUI
#if os(iOS)
import UIKit
#endif

struct VisualIntelligenceHUD: View {
    @Bindable var viewModel: VisualIntelligenceViewModel
    @Binding var isEnteringCustomContext: Bool
    @Binding var showingFullScreenReview: Bool
    @Binding var showingIntelligenceView: Bool
    @Binding var showingSpatialAR: Bool
    let orientation: UIDeviceOrientation
    let onResultSelected: (IntelligenceResult) -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            if viewModel.isReviewing {
                reviewHUD
            } else {
                shutterHUD
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isReviewing)
        // Note: zIndex is handled by the parent ZStack container
    }
    
    @ViewBuilder
    private var reviewHUD: some View {
        ZStack {
            // Toast-style Pipeline Status Overlay
            VStack {
                if viewModel.pipelineStatus != .idle && viewModel.pipelineStatus != .complete {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                        Text(viewModel.pipelineStatus.displayText)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassCapsule()
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.pipelineStatus)
                }
                Spacer()
            }
            .padding(.top, 100) // Below location bar
            .zIndex(100)
            
            // Bottom Control Cluster
            VStack {
                Spacer()
                
                HStack(spacing: 16) {
                    // Live Camera Thumbnail (Picture-in-Picture)
                    Button {
                        viewModel.reCapture()
                    } label: {
                        Group {
                            // Show live camera feed
                            CameraPreviewView(session: viewModel.cameraManager.session)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 80) // Portrait ratio
                                .clipped()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .frame(width: 60, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 5)
                    }
                        
                    
                    // Add Image (+)
                    Button { viewModel.cameraManager.capturePhoto() } label: {
                        Image(systemName: "plus").font(.title3.bold()).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glass(cornerRadius: 22)
                    
                    // Re-Capture (small, left side)
                    Button { withAnimation { viewModel.reCapture() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glass(cornerRadius: 22)
                    
                    Spacer()
                    
                    // Intelligence Button (sparkles) - Large, right side, disabled until first analysis
                    Button { showingIntelligenceView = true } label: {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(viewModel.hasCompletedFirstAnalysis ? .white : .white.opacity(0.4))
                            .padding(20)
                    }
                    .glass(cornerRadius: 35)
                    .disabled(!viewModel.hasCompletedFirstAnalysis)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder
    private var shutterHUD: some View {
        ZStack {
            Button { viewModel.handleCapture() } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 84, height: 84)
                    Circle().fill(.white).frame(width: 72, height: 72)
                }
            }
            .rotationEffect(angleForOrientation(orientation))
            
            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3).foregroundStyle(.white).padding(12).glass(cornerRadius: 25)
                    .rotationEffect(angleForOrientation(orientation))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 30)
            
            // AR Mode Button
            Button {
                showingSpatialAR = true
            } label: {
                Image(systemName: "cube.transparent")
                    .font(.title3).foregroundStyle(.white).padding(12).glass(cornerRadius: 25)
                    .rotationEffect(angleForOrientation(orientation))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 30)
        }
        .padding(.bottom, 30)
        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
        .fullScreenCover(isPresented: $showingSpatialAR) {
            SpatialScoreOverlayView()
        }
    }
    
    private func angleForOrientation(_ orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }
}

// MARK: - iOS 26 Visual Language

extension View {
    /// Applies the system-standard glass effect on iOS 26+, falling back to ultraThinMaterial on older OS.
    @ViewBuilder
    func glass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, macOS 19.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
    
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, macOS 19.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Dynamic Status Pill

struct TopStatusPill: View {
    let result: IntelligenceResult?
    let isRecording: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Sifting...")
                    .fontWeight(.medium)
            } else if let result = result {
                Image(systemName: result.icon)
                    .font(.body)
                Text(result.title)
                    .fontWeight(.medium)
            } else {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.body)
                Text("Scanning")
                    .fontWeight(.medium)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glass(cornerRadius: 25)
        .animation(.smooth, value: result?.title)
        .animation(.smooth, value: isRecording)
    }
}
