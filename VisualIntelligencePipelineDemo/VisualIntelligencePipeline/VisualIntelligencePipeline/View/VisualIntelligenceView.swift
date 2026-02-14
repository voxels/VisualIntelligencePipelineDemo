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
    @StateObject private var viewModel = VisualIntelligenceViewModel()
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

// MARK: - Layer Components

struct VisualIntelligenceReviewLayer: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @State private var currentIndex: Int = 0
    
    var body: some View {
        if let videoURL = viewModel.capturedVideoURL {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.sessionImages.isEmpty {
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
                
                // Page indicator dots
                HStack(spacing: 6) {
                    ForEach(0..<viewModel.sessionImages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 8)
            }
            .background(Color.black)
        } else if let capturedImage = viewModel.capturedImage {
            Image(uiImage: capturedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
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
}

struct VisualIntelligenceCameraLayer: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    
    var body: some View {
        CameraPreviewView(session: viewModel.cameraManager.session)
            .ignoresSafeArea()
    }
}

struct VisualIntelligenceHUD: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Binding var isEnteringCustomContext: Bool
    @Binding var showingFullScreenReview: Bool
    @Binding var showingIntelligenceView: Bool
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
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
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
                        // Resumes live camera mode
                        withAnimation {
                            viewModel.reCapture()
                        }
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
                            .frame(width: 44, height: 44).glass(cornerRadius: 22)
                    }
                    
                    // Re-Capture (small, left side)
                    Button { withAnimation { viewModel.reCapture() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glass(cornerRadius: 22)
                    }
                    
                    Spacer()
                    
                    // Intelligence Button (sparkles) - Large, right side, disabled until first analysis
                    Button { showingIntelligenceView = true } label: {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(viewModel.hasCompletedFirstAnalysis ? .white : .white.opacity(0.4))
                            .padding(20)
                            .glass(cornerRadius: 35)
                    }
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
        }
        .padding(.bottom, 30)
        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
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
        case .siftedSubject(let observation, _):
            withAnimation {
                if viewModel.activeObservation != nil {
                    viewModel.activeObservation = nil
                } else {
                    viewModel.activeObservation = observation
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

// MARK: - Consolidated Dependencies

struct SessionLocationBar: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    
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
                    // Feedback
                    #if os(iOS)
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = viewModel.isLocationPinned ? .heavy : .light
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
                    #endif
                } label: {
                    Image(systemName: viewModel.isLocationPinned ? "pin.fill" : "pin")
                        .font(.body)
                        .foregroundStyle(viewModel.isLocationPinned ? .yellow : .white.opacity(0.5))
                        .padding(8)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.black.opacity(0.4))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

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
        case .failed: return .red
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
        case .failed: return "Analysis Failed"
        case .idle: return "Waiting for capture"
        }
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

struct ContextChipBar: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
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
                            .background(.ultraThinMaterial)
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
                                        .background(.ultraThinMaterial)
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

extension VisualIntelligenceView {

}

struct DocumentDetailView: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var hasSaved = false
    
    // OCR Text Editing State
    @State private var editableText: String = ""
    @State private var isTextExpanded: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Image Section
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                }
                .frame(maxHeight: isTextExpanded ? UIScreen.main.bounds.height * 0.4 : .infinity)
                
                // OCR Text Section
                if !editableText.isEmpty || viewModel.rectifiedDocumentText != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        // Header with toggle
                        HStack {
                            Text("Recognized Text")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isTextExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(isTextExpanded ? "Collapse" : "Expand")
                                        .font(.caption)
                                    Image(systemName: isTextExpanded ? "chevron.down" : "chevron.up")
                                }
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        .padding(.horizontal)
                        
                        if isTextExpanded {
                            // Editable Text Area
                            TextEditor(text: $editableText)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .font(.body)
                                .frame(minHeight: 150, maxHeight: 300)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            
                            // Copy button
                            HStack {
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = editableText
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Label("Copy Text", systemImage: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .padding(.horizontal)
                            }
                        } else {
                            // Preview (collapsed state)
                            Text(editableText.prefix(100) + (editableText.count > 100 ? "..." : ""))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.9))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.black)
            .navigationTitle("Scanned Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if hasSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.bold())
                    } else {
                        Button {
                            // Sync edited text back to ViewModel before saving
                            viewModel.rectifiedDocumentText = editableText
                            viewModel.saveDocument()
                            hasSaved = true
                        } label: {
                            if viewModel.isSavingDocument {
                                ProgressView()
                            } else {
                                Text("Save to Visual Intelligence")
                                    .fontWeight(.bold)
                            }
                        }
                        .disabled(viewModel.isSavingDocument)
                    }
                    
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Scanned Document", image: Image(uiImage: image)))
                }
            }
            .onAppear {
                // Initialize editable text from ViewModel
                editableText = viewModel.rectifiedDocumentText ?? ""
                // Auto-expand if there's text to show
                if !editableText.isEmpty {
                    isTextExpanded = true
                }
            }
        }
    }
}

// MARK: - WebView Helper
struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
}

struct FullScreenImageView: View {
    let image: UIImage // Fallback/Single
    var sessionImages: [UIImage] = []
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: UIImage?
    
    init(image: UIImage, sessionImages: [UIImage] = []) {
        self.image = image
        self.sessionImages = sessionImages
        _selectedImage = State(initialValue: image)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !sessionImages.isEmpty {
                TabView(selection: $selectedImage) {
                    ForEach(sessionImages, id: \.self) { img in
                        GeometryReader { proxy in
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .tag(img as UIImage?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            
            // Interaction overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .padding()
                            .shadow(radius: 5)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Intelligence Results View (Split Screen)

/// Intelligence Results View - Detailed results screen pushed from Capture View
struct IntelligenceResultsView: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEnteringCustomContext = false
    @State private var customContextText = ""
    @State private var showingTextEditor = false // Toggle between image and text
    
    let onSave: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Location Bar at Top
                SessionLocationBar(viewModel: viewModel)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Image/TextEditor Section with Toggle
                        VStack(spacing: 12) {
                            // Toggle Buttons
                            HStack(spacing: 12) {
                                Button {
                                    withAnimation { showingTextEditor = false }
                                } label: {
                                    Text("Image")
                                        .font(.caption.bold())
                                        .foregroundStyle(showingTextEditor ? .white.opacity(0.6) : .white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(showingTextEditor ? Color.white.opacity(0.1) : Color.blue)
                                        .clipShape(Capsule())
                                }
                                
                                Button {
                                    withAnimation { showingTextEditor = true }
                                } label: {
                                    Text("Notes")
                                        .font(.caption.bold())
                                        .foregroundStyle(showingTextEditor ? .white : .white.opacity(0.6))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(showingTextEditor ? Color.blue : Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            
                            // Content
                            if showingTextEditor {
                                TextEditor(text: Binding(
                                    get: { customContextText },
                                    set: { customContextText = $0 }
                                ))
                                .frame(height: 200)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                            } else if let image = viewModel.capturedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.3), radius: 10)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Sectioned Grid of Buttons
                        VStack(spacing: 24) {
                            // Action Buttons Section
                            if !actionButtons.isEmpty {
                                buttonSection(title: "ACTIONS", buttons: actionButtons, columns: 2)
                            }
                            
                            // Context Buttons Section  
                            if !contextButtons.isEmpty {
                                buttonSection(title: "CONTEXT", buttons: contextButtons, columns: 1, isContext: true)
                            }
                            
                            // Detected Buttons Section
                            if !detectedButtons.isEmpty {
                                buttonSection(title: "DETECTED", buttons: detectedButtons, columns: 2)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 100) // Space for fixed save button
                }
                
                // Fixed Save Button at Bottom
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.2))
                    
                    Button {
                        onSave()
                    } label: {
                        HStack(spacing: 12) {
                            if viewModel.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill").font(.body.bold())
                                Text("Save Capture").fontWeight(.bold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.isSaving ? Color.gray : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color.black.opacity(0.95))
            }
        }
        .navigationTitle("Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Dismiss") {
                    viewModel.shouldDismiss = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showingPlaceSelection) {
            PlaceSelectionMapView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingDocumentView) {
            if let doc = viewModel.rectifiedDocument {
                DocumentDetailView(viewModel: viewModel, image: doc)
            }
        }
        .onAppear {
            // Initialize text editor with document OCR text if available
            if customContextText.isEmpty {
                let documentText = viewModel.results.compactMap { result -> String? in
                    if case .document(_, let text, _, _) = result {
                        return text
                    }
                    return nil
                }.joined(separator: "\n\n")
                
                if !documentText.isEmpty {
                    customContextText = documentText
                }
            }
        }
        .alert("Add Context", isPresented: $isEnteringCustomContext) {
            TextField("E.g. Gift for Mom", text: $customContextText)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                viewModel.addUserContext(customContextText)
                customContextText = ""
            }
        } message: {
            Text("Add a custom label or purpose to this capture.")
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func resultCard(for result: IntelligenceResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.icon)
                    .font(.title3)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.8))
            
            Text(result.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
            
            let subtitle = result.subtitle
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func contextChip(text: String) -> some View {
        let isSelected = viewModel.selectedPurposes.contains(text)
        Button {
            withAnimation {
                if isSelected {
                    viewModel.selectedPurposes.remove(text)
                } else {
                    viewModel.selectedPurposes.insert(text)
                }
            }
        } label: {
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.white.opacity(0.2))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
    
    private var allContexts: [String] {
        // Get purpose suggestions from results
        let suggestions: [String]
        if let purposeResult = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
           case .purpose(let statements) = purposeResult {
            suggestions = statements
        } else {
            suggestions = []
        }
        
        // Combine selected and unselected, remove duplicates
        let selected = Array(viewModel.selectedPurposes)
        let unselected = suggestions.filter { !viewModel.selectedPurposes.contains($0) }
        return (selected + unselected).sorted()
    }
    
    // MARK: - Button Categorization
    
    private var actionButtons: [(String, String, () -> Void)] {
        var buttons: [(String, String, () -> Void)] = []
        
        for result in viewModel.results {
            switch result {
            case .qr(let url):
                buttons.append(("QR Code", "qrcode", {
                    UIApplication.shared.open(url)
                }))
            case .richWeb(let url, _):
                buttons.append(("Open Link", "link", {
                    UIApplication.shared.open(url)
                }))
            case .document(let obs, _, _, let rectifiedData):
                buttons.append(("View Document", "doc.text", {
                    viewModel.handleDocumentSelection(obs, rectifiedImageData: rectifiedData)
                }))
            default:
                break
            }
        }
        
        return buttons
    }
    
    private var contextButtons: [(String, String, () -> Void)] {
        let contexts = allContexts
        return contexts.prefix(6).map { context in
            (context, "tag", {
                withAnimation {
                    if viewModel.selectedPurposes.contains(context) {
                        viewModel.selectedPurposes.remove(context)
                    } else {
                        viewModel.selectedPurposes.insert(context)
                    }
                }
            })
        }
    }
    
    private var detectedButtons: [(String, String, () -> Void)] {
        var buttons: [(String, String, () -> Void)] = []
        
        for result in viewModel.results {
            switch result {
            case .semantic(let label, _):
                buttons.append((label.capitalized, "eye", {
                    withAnimation {
                        if viewModel.selectedPurposes.contains(label) {
                            viewModel.selectedPurposes.remove(label)
                            if viewModel.sessionTitle == label { viewModel.sessionTitle = nil }
                        } else {
                            viewModel.selectedPurposes.insert(label)
                            viewModel.sessionTitle = label
                        }
                    }
                }))
            case .product(let code, _, _):
                let text = "Barcode: \(code)"
                buttons.append(("Barcode", "barcode", {
                    withAnimation {
                        if viewModel.selectedPurposes.contains(text) {
                            viewModel.selectedPurposes.remove(text)
                        } else {
                            viewModel.selectedPurposes.insert(text)
                        }
                    }
                }))
            case .siftedSubject(let observation, let label):
                if let label = label {
                    buttons.append((label, "viewfinder", {
                        withAnimation {
                            if viewModel.activeObservation != nil {
                                viewModel.activeObservation = nil
                            } else {
                                viewModel.activeObservation = observation
                            }
                        }
                    }))
                }
            default:
                break
            }
        }
        
        return buttons
    }
    
    @ViewBuilder
    private func buttonSection(title: String, buttons: [(String, String, () -> Void)], columns: Int, isContext: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with optional regenerate button for CONTEXT
            if title == "CONTEXT" {
                HStack {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await viewModel.regenerateContextSuggestions(for: viewModel.selectedPlace)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } else {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 12) {
                ForEach(0..<buttons.count, id: \.self) { index in
                    let button = buttons[index]
                    Button {
                        button.2()
                    } label: {
                        if isContext {
                            // Context buttons: no icon, multiline text, visual selection state
                            let isSelected = viewModel.selectedPurposes.contains(button.0)
                            Text(button.0)
                                .font(.caption.bold())
                                .foregroundStyle(isSelected ? .black : .white)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .background(isSelected ? Color.white : Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            // Action/Detected buttons: icon + text with selection state
                            let isSelected = viewModel.selectedPurposes.contains(button.0) || 
                                           viewModel.selectedPurposes.contains(where: { $0.contains(button.0) })
                            VStack(spacing: 8) {
                                Image(systemName: button.1)
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.8))
                                
                                Text(button.0)
                                    .font(.caption.bold())
                                    .foregroundStyle(isSelected ? .blue : .white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Content Stack (broken out to help type-checker)
    
    @ViewBuilder
    private var intelligenceContentStack: some View {
        VStack(spacing: 20) {
            // Pipeline Status
            if viewModel.pipelineStatus != .idle && viewModel.pipelineStatus != .complete {
                PipelineStatusView(status: viewModel.pipelineStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            
            // Save Chip
            saveSection
            
            // Actions Section
            if !actionResults.isEmpty {
                actionsSection
            }
            
            // Context Section
            contextSection
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var saveSection: some View {
        HStack {
            Button {
                onSave()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill").font(.body.bold())
                        Text("Save Capture").fontWeight(.bold)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(viewModel.isSaving ? Color.gray : Color.blue)
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.isSaving)
            
            Spacer()
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIONS")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(actionResults, id: \.self) { result in
                        Button {
                            handleResultSelection(result)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: result.icon)
                                Text(result.title).fontWeight(.medium)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.green.opacity(0.3))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTEXT")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Custom Button
                    Button {
                        isEnteringCustomContext = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add")
                        }
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    
                    // Selected Contexts
                    ForEach(Array(viewModel.selectedPurposes).sorted(), id: \.self) { context in
                        contextChip(text: context, isSelected: true)
                    }
                    
                    // AI Suggestions
                    ForEach(purposeSuggestions, id: \.self) { statement in
                        contextChip(text: statement, isSelected: false)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private func contextChip(text: String, isSelected: Bool) -> some View {
        Button {
            toggleContext(text)
        } label: {
            HStack(spacing: 4) {
                Text(text)
                if isSelected {
                    Image(systemName: "checkmark").font(.caption.bold())
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
    }
    
    // MARK: - Helpers
    
    private var actionResults: [IntelligenceResult] {
        let documents = viewModel.results.filter { if case .document = $0 { return true }; return false }
        let others = viewModel.results.filter {
            if case .qr = $0 { return true }
            if case .richWeb = $0 { return true }
            return false
        }
        return documents + others
    }
    
    private var purposeSuggestions: [String] {
        guard let purposeResult = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
              case .purpose(let statements) = purposeResult else {
            return []
        }
        return statements.filter { !viewModel.selectedPurposes.contains($0) }
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
    
    private func handleResultSelection(_ result: IntelligenceResult) {
        switch result {
        case .document(let obs, let text, _, let rectifiedData):
            viewModel.handleDocumentSelection(obs, text: text, rectifiedImageData: rectifiedData)
        case .qr(let url):
            UIApplication.shared.open(url)
        case .richWeb(let url, _):
            UIApplication.shared.open(url)
        default:
            break
        }
    }
}
