import SwiftUI
import DiverKit
import DiverShared
import Vision
import Photos
import PhotosUI
import WebKit
import MapKit
import AVKit

/// Agent [DESIGN] - Unified Shutter UI (iOS 26)
public struct VisualIntelligenceView: View {
    @State private var viewModel = VisualIntelligenceViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationManager: NavigationManager
    
    @State private var orientation: UIDeviceOrientation = .portrait
    
    // Identifiable wrapper for the review image
    struct ReviewImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    
    @State private var reviewImage: ReviewImage?
    
    // Custom Context Input
    @State private var isEnteringCustomContext = false
    @State private var showingFullScreenReview = false
    @State private var showingIntelligenceView = false
    @State private var showingSpatialAR = false
    @State private var customContextText = ""
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer
                navigationLayer
                hudLayer
            }
            .onAppear {
                if let scanID = navigationManager.scanSessionID {
                    viewModel.activeSessionID = scanID
                    print("🔄 Visual Intelligence: Resuming session \(scanID)")
                } else {
                    // Fresh session — clear any stale context from a previous session
                    viewModel.activeSessionID = UUID().uuidString
                    viewModel.accumulatedContexts = []
                    print("🆕 Visual Intelligence: Starting fresh session \(viewModel.activeSessionID)")
                }
                
                // Check for pending photo imports from sidebar
                if !navigationManager.pendingImportItems.isEmpty {
                    let items = navigationManager.pendingImportItems
                    navigationManager.pendingImportItems = []
                    viewModel.processImportedPhotos(items)
                    // Camera NOT started — import mode
                } else {
                    viewModel.cameraManager.startSession()
                    viewModel.setupCameraBridge()
                }
                
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                    let newOrientation = UIDevice.current.orientation
                    if newOrientation.isValidInterfaceOrientation {
                        self.orientation = newOrientation
                        Task { @MainActor in
                            viewModel.currentOrientation = visionOrientation(from: newOrientation)
                        }
                    }
                }
                
                Task { @MainActor in
                    viewModel.checkPendingReprocess()
                    if let scanID = navigationManager.scanSessionID {
                        viewModel.locateContextOnLoad(subservientTo: scanID)
                        await viewModel.resumeSessionContext(scanID)
                    } else {
                        viewModel.locateContextOnLoad(subservientTo: nil)
                    }
                }
            }
            .onChange(of: viewModel.activeObservation) { oldVal, newVal in
                withAnimation(.linear(duration: 0.2)) {
                    viewModel.updatePeelAmount(newVal != nil ? 0.3 : 0.0)
                }
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
                // Don't reset here - navigation to intelligence view triggers onDisappear
                // Reset will happen when shouldDismiss triggers via onChange
            }
            .navigationTitle("Visual Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Dismiss") {
                        withAnimation {
                            navigationManager.isScanActive = false
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $viewModel.showingPlaceSelection) {
                PlaceSelectionMapView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingDocumentView) {
                if let doc = viewModel.rectifiedDocument {
                    DocumentDetailView(viewModel: viewModel, image: doc)
                }
            }
            .alert("Add Context", isPresented: $isEnteringCustomContext) {
                TextField("E.g. Gift for Mom", text: $customContextText)
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    viewModel.addUserContext(customContextText)
                }
            } message: {
                Text("Add a custom label or purpose to this capture.")
            }
            .alert("Save Failed", isPresented: $viewModel.showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.saveErrorMessage ?? "An unknown error occurred.")
            }
            .fullScreenCover(isPresented: $showingFullScreenReview) {
                if let image = viewModel.capturedImage {
                    FullScreenImageView(image: image, sessionImages: viewModel.sessionImages)
                }
            }
            .onChange(of: viewModel.shouldDismiss) {_, newValue in
                if newValue {
                    withAnimation {
                        navigationManager.isScanActive = false
                    }
                    // Reset VM now that user is dismissing the entire capture session
                    viewModel.reset()
                }
            }
            .navigationDestination(isPresented: $showingIntelligenceView) {
                IntelligenceResultsView(viewModel: viewModel) {
                    viewModel.commitReviewSave()
                }
            }
        }
    }
    
    // MARK: - Layer Decomposition
    
    @ViewBuilder
    private var backgroundLayer: some View {
        Group {
            if viewModel.isReviewing {
                VisualIntelligenceReviewLayer(viewModel: viewModel)
            } else if viewModel.cameraManager.isReady {
                VisualIntelligenceCameraLayer(viewModel: viewModel)
            } else {
                bootingLayer
            }
        }
    }
    
    @ViewBuilder
    private var navigationLayer: some View {
        VStack(spacing: 0) {
            // Top Stack: Location only (Context moved to Intelligence View)
            
            SessionLocationBar(viewModel: viewModel)
                .padding(.top, 8)
            
            Spacer()
        }
        .zIndex(100)
    }
    
    @ViewBuilder
    private var hudLayer: some View {
        VisualIntelligenceHUD(
            viewModel: viewModel,
            isEnteringCustomContext: $isEnteringCustomContext,
            showingFullScreenReview: $showingFullScreenReview,
            showingIntelligenceView: $showingIntelligenceView,
            showingSpatialAR: $showingSpatialAR,
            orientation: orientation,
            onResultSelected: { result in
                handleResultSelection(result)
            }
        )
        .zIndex(20)
    }
    
    private func angleForOrientation(_ orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }
    
    private func visionOrientation(from device: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch device {
        case .portrait: return .right
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var bootingLayer: some View {
        Color.black.ignoresSafeArea()
        VStack {
            ProgressView().tint(.white)
            Text("Booting Visual Intelligence...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top)
        }
    }
}

extension VisualIntelligenceView {
    // Helper to bridge the new View callback to the existing logic
    func handleResultSelection(_ result: IntelligenceResult) {
        switch result {
        case .document(let obs, _, _, let rectifiedData):
            viewModel.handleDocumentSelection(obs, rectifiedImageData: rectifiedData)
        case .text(let text, let url):
            if let url {
                UIApplication.shared.open(url)
            } else {
                navigationManager.searchQuery = text
                navigationManager.isSearching = true
                navigationManager.isScanActive = false
            }
        case .product, .entertainment, .qr, .richWeb:
            if let url = result.primaryURL {
                UIApplication.shared.open(url)
            }
        case .siftedSubject(let mask, _, _):
            withAnimation {
                if viewModel.activeObservation != nil {
                    viewModel.activeObservation = nil
                } else {
                    viewModel.activeObservation = mask
                }
            }
        default:
            let resultText = result.title
            withAnimation {
                if viewModel.selectedPurposes.contains(resultText) {
                    viewModel.selectedPurposes.remove(resultText)
                    if viewModel.sessionTitle == resultText { viewModel.sessionTitle = nil }
                } else {
                    viewModel.selectedPurposes.insert(resultText)
                    viewModel.sessionTitle = resultText
                }
            }
        }
    }
}
