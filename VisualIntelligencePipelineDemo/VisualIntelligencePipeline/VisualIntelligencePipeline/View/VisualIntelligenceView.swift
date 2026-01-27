import SwiftUI
import DiverKit
import DiverShared
import Vision
import Photos
import PhotosUI
import WebKit
import MapKit

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
    @State private var customContextText = ""
    
    public init() {}
    
    public var body: some View {
        ZStack {
            backgroundLayer
            navigationLayer
            hudLayer
        }
        .onAppear {
            viewModel.cameraManager.startSession()
            viewModel.setupCameraBridge()
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
            }
        }
        .onChange(of: viewModel.activeObservation) { oldVal, newVal in
            withAnimation(.linear(duration: 0.2)) {
                viewModel.updatePeelAmount(newVal != nil ? 0.3 : 0.0)
            }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            viewModel.reset()
        }
        .navigationTitle("Visual Intelligence")
        .navigationBarTitleDisplayMode(.inline)
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
                FullScreenImageView(image: image)
            }
        }
    }
    
    // MARK: - Layer Decomposition
    
    @ViewBuilder
    private var backgroundLayer: some View {
        AnyView(
            Group {
                if viewModel.isReviewing {
                    VisualIntelligenceReviewLayer(viewModel: viewModel)
                } else if viewModel.cameraManager.isReady {
                    VisualIntelligenceCameraLayer(viewModel: viewModel)
                } else {
                    bootingLayer
                }
            }
        )
    }
    
    @ViewBuilder
    private var navigationLayer: some View {
        AnyView(
            VStack(spacing: 0) {
                HStack {
                     Button {
                        navigationManager.isScanActive = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .glass(cornerRadius: 30)
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal, 20)
                
                SessionLocationBar(viewModel: viewModel)
                    .padding(.top, 8)
                
                Spacer()
            }
            .zIndex(100)
        )
    }
    
    @ViewBuilder
    private var hudLayer: some View {
        AnyView(
            VisualIntelligenceHUD(
                viewModel: viewModel,
                isEnteringCustomContext: $isEnteringCustomContext,
                showingFullScreenReview: $showingFullScreenReview,
                orientation: orientation,
                onResultSelected: { result in
                    handleResultSelection(result)
                }
            )
            .zIndex(20)
        )
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
    
    var body: some View {
        if let capturedImage = viewModel.capturedImage {
            Image(uiImage: capturedImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .overlay(
                    ZStack {
                        if let siftedImage = viewModel.siftedImage, let box = viewModel.siftedBoundingBox {
                             SiftedSubjectView(siftedImage: siftedImage, boundingBox: box, peelAmount: $viewModel.peelAmount)
                        } else if let box = viewModel.siftedBoundingBox {
                            GeometryReader { proxy in
                                let rect = viewModel.convertBoundingBox(box, to: proxy.size)
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(LinearGradient(colors: [.white, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                )
        } else {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text("Unable to load image for reprocessing")
                    .foregroundStyle(.white)
                Button("Cancel") {
                    viewModel.isReviewing = false
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct VisualIntelligenceCameraLayer: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    
    var body: some View {
        CameraPreviewView(session: viewModel.cameraManager.session)
            .ignoresSafeArea()
            .overlay(
                ZStack {
                    if let box = viewModel.siftedBoundingBox, let image = viewModel.siftedImage {
                        SiftedSubjectView(siftedImage: image, boundingBox: box, peelAmount: $viewModel.peelAmount)
                    } else if let box = viewModel.siftedBoundingBox {
                        GeometryReader { proxy in
                            let rect = viewModel.convertBoundingBox(box, to: proxy.size)
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(LinearGradient(colors: [.white, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            )
    }
}

struct VisualIntelligenceHUD: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Binding var isEnteringCustomContext: Bool
    @Binding var showingFullScreenReview: Bool
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
        VStack(spacing: 16) {
            if viewModel.pipelineStatus != .idle && viewModel.pipelineStatus != .complete {
                PipelineStatusView(status: viewModel.pipelineStatus)
                    .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
            
            if let mediaResult = viewModel.results.first(where: { !$0.assets.isEmpty }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(mediaResult.assets, id: \.self) { url in
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack { Color.white.opacity(0.1); ProgressView().tint(.white) }
                            }
                            .frame(width: 140, height: 210)
                            .cornerRadius(12)
                            .glass(cornerRadius: 16)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 220)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            }
            
            if !viewModel.results.isEmpty {
                ResultsOverlayView(results: viewModel.sortedResults) { result in
                    onResultSelected(result)
                }
            }
            
            ContextChipBar(viewModel: viewModel, isEnteringCustomContext: $isEnteringCustomContext)
                .padding(.vertical, 8)
            
            // Control Cluster
            HStack(spacing: 20) {
                Button { showingFullScreenReview = true } label: {
                    Group {
                        if let siftedImage = viewModel.siftedImage {
                            #if canImport(UIKit)
                            Image(uiImage: siftedImage).resizable().scaledToFit()
                            #elseif canImport(AppKit)
                            Image(nsImage: siftedImage).resizable().scaledToFit()
                            #endif
                        } else if let image = viewModel.capturedImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.2).overlay(ProgressView().tint(.white))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .glass(cornerRadius: 12)
                }
                
                Button { viewModel.cameraManager.capturePhoto() } label: {
                    Image(systemName: "plus").font(.title3.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44).glass(cornerRadius: 22)
                }
                
                Button { viewModel.reprocessPipeline() } label: {
                    Image(systemName: "sparkles").font(.title3.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44).glass(cornerRadius: 22)
                }
                
                Spacer()
                
                Button { withAnimation { viewModel.reCapture() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(.white)
                        .padding(20).glass(cornerRadius: 35)
                }
                
                Button { viewModel.commitReviewSave() } label: {
                    HStack {
                        if viewModel.isAnalyzing || viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save").fontWeight(.bold)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)
                    .background((viewModel.isAnalyzing || viewModel.isSaving ? Color.gray : Color.blue), in: RoundedRectangle(cornerRadius: 35))
                    .glass(cornerRadius: 35)
                }
                .disabled(viewModel.isAnalyzing || viewModel.isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
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
            
            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .any(of: [.images, .videos])) {
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
            AnyView(self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius)))
        } else {
            AnyView(self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius)))
        }
    }
    
    func glassCapsule() -> some View {
        if #available(iOS 26.0, macOS 19.0, *) {
            AnyView(self.glassEffect(.regular, in: Capsule()))
        } else {
            AnyView(self.background(.ultraThinMaterial, in: Capsule()))
        }
    }
}

extension VisualIntelligenceView {
    // Helper to bridge the new View callback to the existing logic
    func handleResultSelection(_ result: IntelligenceResult) {
        switch result {
        case .document(let obs, _, _):
            viewModel.handleDocumentSelection(obs)
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
        case .siftedSubject(let obs):
            withAnimation {
                if viewModel.activeObservation != nil {
                    viewModel.activeObservation = nil
                } else {
                    viewModel.activeObservation = obs.0
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

struct ContextChipBar: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Binding var isEnteringCustomContext: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Header
            HStack {
                Text("Describe Context")
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
            }
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
                            viewModel.saveDocument()
                            hasSaved = true
                        } label: {
                            if viewModel.isSavingDocument {
                                ProgressView()
                            } else {
                                Text("Save to Diver")
                                .fontWeight(.bold)
                            }
                        }
                        .disabled(viewModel.isSavingDocument)
                    }
                    
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Scanned Document", image: Image(uiImage: image)))
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
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                Image(uiImage: image) // Assuming image is safe to unwrap or passed directly
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
            
            // Interaction overlay
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
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
    }
}
