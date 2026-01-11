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
    @State private var customContextText = ""
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Background Layer
            // Background Layer
            if viewModel.cameraManager.isReady {
                CameraPreviewView(session: viewModel.cameraManager.session)
                    .ignoresSafeArea()
                    .overlay(
                        ZStack {
                            // Highlight Subject
                            if let box = viewModel.siftedBoundingBox, let image = viewModel.siftedImage {
                                // Use SiftedSubjectView for the overlay
                                SiftedSubjectView(siftedImage: image, boundingBox: box, peelAmount: $viewModel.peelAmount)
                            } else if let box = viewModel.siftedBoundingBox {
                                // Fallback if image not ready but box is
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
                
                // MARK: - Navigation Control
                VStack {
                    HStack {
                         Button {
                            viewModel.showingPlaceSelection = true
                        } label: {
                            Image(systemName: "map.fill")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(12)
                                .glass(cornerRadius: 30)
                        }
                        
                        Spacer()
                        Button {
                            navigationManager.isScanActive = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(12)
                                .glass(cornerRadius: 30)
                        }
                    }
                    .padding(.top, 50)
                    .padding(.horizontal, 20)
                    Spacer()
                }
                .zIndex(100)
            } else {
                Color.black.ignoresSafeArea()
                VStack {
                    ProgressView()
                        .tint(.white)
                    Text("Booting Visual Intelligence...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top)
                }
            }
            
            
                
                // MARK: - HUD Layer
                VStack {
                    Spacer()
                    
                    if viewModel.isReviewing {
                        // Review Mode HUD
                        VStack(spacing: 16) {
                            
                            // Processing Toast
                            if viewModel.isAnalyzing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.black)
                                        .scaleEffect(0.8)
                                    Text("Analyzing Scene...")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.black)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .glass(cornerRadius: 14)
                                .foregroundStyle(.black)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(100)
                            }
                            
                            // 2. Media Assets Preview (Live Assets)
                            if let mediaResult = viewModel.results.first(where: { !$0.assets.isEmpty }) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(mediaResult.assets, id: \.self) { url in
                                            AsyncImage(url: url) { image in
                                                image.resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                ZStack {
                                                    Color.white.opacity(0.1)
                                                    ProgressView().tint(.white)
                                                }
                                            }
                                            .frame(width: 140, height: 210)
                                            .cornerRadius(12)
                                            .glass(cornerRadius: 16)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .frame(height: 220)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                            
                            // 2.5 Location Selection Row
                            locationSelectionRow
                            
                            // 3. Metadata Overlay
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    resultsOverlay
                                }
                                .padding(.horizontal)
                            }
                            
                            if let purposeResult = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
                               case .purpose(let statements) = purposeResult {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Suggested Context") // Updated title
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white.opacity(0.8))
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            // 1. Custom Context Entry Pill
                                            Button {
                                                customContextText = ""
                                                isEnteringCustomContext = true
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "pencil.line")
                                                    Text("Write Context...")
                                                }
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Color.white.opacity(0.1))
                                                .clipShape(Capsule())
                                                .foregroundStyle(.white)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.white.opacity(0.3), lineWidth: 1) // Dashed? No, solid is fine.
                                                )
                                            }

                                            // 2. Selected Items (Persisted)
                                            ForEach(Array(viewModel.selectedPurposes).sorted(), id: \.self) { selected in
                                                Button {
                                                    withAnimation {
                                                        viewModel.selectedPurposes.remove(selected)
                                                        if viewModel.sessionTitle == selected { viewModel.sessionTitle = nil }
                                                    }
                                                    #if os(iOS)
                                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                    #endif
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(selected)
                                                        Image(systemName: "xmark")
                                                            .font(.caption2.bold())
                                                    }
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 10)
                                                    .background(Color.blue)
                                                    .clipShape(Capsule())
                                                    .foregroundStyle(.white)
                                                    .overlay(
                                                        Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                                    )
                                                }
                                            }

                                            // 3. Suggestions (Refinement Triggers)
                                            ForEach(statements, id: \.self) { statement in
                                                if !viewModel.selectedPurposes.contains(statement) {
                                                    Button {
                                                        withAnimation {
                                                            viewModel.selectedPurposes.insert(statement)
                                                            // Trigger Drill Down / Refinement
                                                            viewModel.refineContext(with: statement)
                                                        }
                                                        #if os(iOS)
                                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                        #endif
                                                    } label: {
                                                        Text(statement)
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)
                                                            .padding(.horizontal, 16)
                                                            .padding(.vertical, 10)
                                                            .background(Color.white.opacity(0.1))
                                                            .clipShape(Capsule())
                                                            .foregroundStyle(.white)
                                                            .overlay(
                                                                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                                            )
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            // Control Cluster
                            HStack(spacing: 20) {
                                // Thumbnail (Captured Image)
                                Group {
                                    // Use the cached sifted image from ViewModel if available
                                    if let siftedImage = viewModel.siftedImage {
                                        #if canImport(UIKit)
                                        Image(uiImage: siftedImage)
                                            .resizable()
                                            .scaledToFit() // Fit so key subject is visible
                                        #elseif canImport(AppKit)
                                        Image(nsImage: siftedImage)
                                            .resizable()
                                            .scaledToFit()
                                        #endif
                                    }
                                    else if let image = viewModel.capturedImage {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        // Skeleton Thumbnail
                                        Color.white.opacity(0.2)
                                            .overlay(ProgressView().tint(.white))
                                    }
                                }
                                .frame(width: 60, height: 60)
                                .glass(cornerRadius: 12)
                                .overlay(alignment: .topTrailing) {
                                    if viewModel.sessionImages.count > 1 {
                                        Text("\(viewModel.sessionImages.count)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.black)
                                            .padding(6)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                            .offset(x: 10, y: -10)
                                    }
                                }
                                
                                // Add Button (Multi-Image)
                                Button {
                                    viewModel.cameraManager.capturePhoto()
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.title3.bold()) // Slightly bolder
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .glass(cornerRadius: 22)
                                }
                                
                                // Reprocess / Refresh Button
                                Button {
                                    viewModel.reprocessPipeline()
                                } label: {
                                    Image(systemName: "sparkles")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .glass(cornerRadius: 22)
                                }

                                
                                Spacer()
                                
                                // Re-Capture Button (Refresh)
                                Button {
                                    withAnimation { viewModel.reCapture() }
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .padding(20)
                                        .glass(cornerRadius: 35)
                                }
                                
                                // Save Button
                                Button {
                                    viewModel.commitReviewSave()
                                    // Feedback only, do not auto dismiss unless desired
                                } label: {
                                    HStack {
                                        if viewModel.isAnalyzing || viewModel.isSaving {
                                            ProgressView().tint(.white)
                                        } else {
                                            Text("Save")
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 20)
                                    .background(
                                        (viewModel.isAnalyzing || viewModel.isSaving ? Color.gray : Color.blue),
                                        in: RoundedRectangle(cornerRadius: 35)
                                    )
                                    .glass(cornerRadius: 35)
                                }
                                .disabled(viewModel.isAnalyzing || viewModel.isSaving)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        
                    } else {
                        // Standard HUD (Shutter)
                        ZStack {
                            // Simple Capture Button
                            Button {
                                viewModel.handleCapture()
                            } label: {
                                ZStack {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 4)
                                        .frame(width: 84, height: 84)
                                    
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 72, height: 72)
                                }
                            }
                            .rotationEffect(angleForOrientation(orientation))
                            
                            // Auxiliary Buttons (Corners)
                            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .padding(12)
                                    .glass(cornerRadius: 25)
                                    .rotationEffect(angleForOrientation(orientation))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 30)
                        }
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isReviewing)
                .zIndex(20)
            }
            .onAppear {
                // Ensure session is started when view appears
                viewModel.cameraManager.startSession()
                viewModel.setupCameraBridge()
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                    let newOrientation = UIDevice.current.orientation
                    if newOrientation.isValidInterfaceOrientation {
                        self.orientation = newOrientation
                        viewModel.currentOrientation = visionOrientation(from: newOrientation)
                    }
                }
            }
            // Use activeObservation to drive subtle highlight (peel effect)
            .onChange(of: viewModel.activeObservation) { oldVal, newVal in
                withAnimation(.linear(duration: 0.2)) {
                    viewModel.updatePeelAmount(newVal != nil ? 0.3 : 0.0)
                }
            }
            // Removed fullScreenCover
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
    
    @ViewBuilder
    private func pillContent(for result: IntelligenceResult, secondaryIcon: String? = nil, isSelected: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.icon)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            
            if let icon = secondaryIcon {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .opacity(0.7)
            } else if result.primaryURL != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .opacity(0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(cornerRadius: 24)
        .background(isSelected ? Color.blue.opacity(0.8) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .foregroundStyle(.white)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1)
        )
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

    /// Applies the system-standard glass effect on iOS 26+ for Capsule shape.
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

extension VisualIntelligenceView {
    @ViewBuilder
    private var resultsOverlay: some View {
        if viewModel.isAnalyzing && viewModel.results.filter({ if case .siftedSubject = $0 { return false }; return true }).isEmpty {
            // Skeleton Loading State
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 8) {
                    Circle().frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 14)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCapsule()
                .opacity(0.5)
            }
        } else {
            ForEach(viewModel.sortedResults, id: \.title) { result in
                if case .siftedSubject = result { EmptyView() }
                else if case .purpose = result { EmptyView() }
                else {
                    VStack(spacing: 8) {
                        resultItem(for: result)
                        
                        // QR / Web Preview
                        if case .qr(let url) = result {
                            WebView(url: url)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 16)
                        } else if case .richWeb(let url, _) = result {
                            WebView(url: url)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func resultItem(for result: IntelligenceResult) -> some View {
        // Unified Behavior: Always Actionable (Preview/Link)
        switch result {
        case .document(let obs, _, _):
            Button {
                viewModel.handleDocumentSelection(obs)
            } label: {
                pillContent(for: result)
            }
        case .text(let text, let url):
            if let url {
                Link(destination: url) {
                    pillContent(for: result, secondaryIcon: "arrow.up.right")
                }
            } else {
                Button {
                    navigationManager.searchQuery = text
                    navigationManager.isSearching = true
                    navigationManager.isScanActive = false // Dismiss scanner to show search
                } label: {
                    pillContent(for: result, secondaryIcon: "magnifyingglass")
                }
            }
        case .product, .entertainment, .qr:
            if let url = result.primaryURL {
                Link(destination: url) {
                    pillContent(for: result, secondaryIcon: "arrow.up.right")
                }
            } else {
                pillContent(for: result)
            }
        case .purpose:
             Button {
                 // No-op or feedback
             } label: {
                 pillContent(for: result)
             }
        default:
            Button {
                let text = result.title
                withAnimation {
                    if viewModel.selectedPurposes.contains(text) {
                        viewModel.selectedPurposes.remove(text)
                        if viewModel.sessionTitle == text { viewModel.sessionTitle = nil }
                    } else {
                        viewModel.selectedPurposes.insert(text)
                        viewModel.sessionTitle = text // Set as explicit title
                    }
                }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                // Show as "active" if it is the explicit title OR just selected
                pillContent(for: result, isSelected: viewModel.selectedPurposes.contains(result.title) || viewModel.sessionTitle == result.title)
            }
        }
    }
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

// MARK: - Map Selection

struct PlaceSelectionMapView: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Wrapper to make EnrichmentData compatible with Map annotations
    struct PlaceAnnotation: Identifiable {
        let id = UUID()
        let data: EnrichmentData
        let coordinate: CLLocationCoordinate2D
    }
    
    @State private var annotations: [PlaceAnnotation] = []
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $region, annotationItems: annotations) { place in
                    MapAnnotation(coordinate: place.coordinate) {
                        Button {
                            viewModel.selectPlace(place.data)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                                    .background(Circle().fill(.white))
                                
                                Text(place.data.title ?? "Unknown")
                                    .font(.caption)
                                    .padding(4)
                                    .background(.thinMaterial)
                                    .cornerRadius(4)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Instructions Overlay
                VStack {
                    Spacer()
                    Text("Select a location to update context")
                    .font(.subheadline)
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(12)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                loadAnnotations()
            }
            .onChange(of: viewModel.selectedPlace?.title) { _ in
                if let data = viewModel.selectedPlace,
                   let lat = data.placeContext?.latitude,
                   let lng = data.placeContext?.longitude {
                    withAnimation {
                        region = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    }
                }
            }
        }
    }
    
    private func loadAnnotations() {
        // Convert candidates to annotations
        let validPlaces = viewModel.placeCandidates.compactMap { data -> PlaceAnnotation? in
            guard let lat = data.placeContext?.latitude,
                  let lng = data.placeContext?.longitude else { return nil }
            return PlaceAnnotation(data: data, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        
        self.annotations = validPlaces
        
        // Center map on results or current location
        if let first = validPlaces.first {
            region = MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        } else {
             Task { @MainActor in
                 if let loc = await Services.shared.locationService?.getCurrentLocation() {
                     region = MKCoordinateRegion(
                        center: loc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                 }
             }
        }
    }
    
}

extension VisualIntelligenceView {
    @ViewBuilder
    var locationSelectionRow: some View {
        if !viewModel.placeCandidates.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Map Icon / "Other"
                    Button {
                        viewModel.showingPlaceSelection = true
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .glass(cornerRadius: 20)
                    }
                    
                    ForEach(Array(viewModel.placeCandidates.enumerated()), id: \.offset) { index, place in
                        Button {
                            withAnimation {
                                viewModel.selectedPlace = place
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        } label: {
                            HStack(spacing: 6) {
                                if place.title == "Home" {
                                    Image(systemName: "house.fill")
                                } else if place.title == "Work" {
                                    Image(systemName: "briefcase.fill")
                                } else {
                                    Image(systemName: "mappin.and.ellipse")
                                }
                                
                                Text(place.title ?? "Unknown")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedPlace?.title == place.title ? Color.blue : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                            .overlay(
                                Capsule()
                                    .stroke(viewModel.selectedPlace?.title == place.title ? Color.white.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
