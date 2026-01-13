//
//  VisualIntelligenceViewModel.swift
//  DiverKit
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import Vision
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif
import Photos
import DiverShared
import CoreImage
import PhotosUI
import AVFoundation
import CoreMedia

// A lightweight wrapper to explicitly allow passing non-Sendable types across concurrency domains.
private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

// Prefer making result types Sendable so they can cross actor boundaries safely.
// If IntelligenceResult and its associated payloads are composed of Sendable types,
// this conformance is safe. If the compiler flags any associated types as non-Sendable,
// consider marking those as Sendable as well, or fall back to using UnsafeSendable wrappers.
extension IntelligenceResult: @unchecked Sendable {}

@MainActor
public class VisualIntelligenceViewModel: ObservableObject {
    // MARK: - App State & Dependencies

    // MARK: - Published UI State
    @Published public var results: [IntelligenceResult] = []
    @Published public var siftedImage: PlatformImage?
    @Published public var siftedBoundingBox: CGRect?
    @Published public var capturedImage: PlatformImage?
    @Published public var sessionImages: [PlatformImage] = [] // For multi-image capture
    @Published public var activeSessionID: String = UUID().uuidString // Session Persistence
    public var accumulatedContexts: [String] = [] // For sequential context history
    @Published public var isReviewing: Bool = false
    @Published public var peelAmount: CGFloat = 0
    @Published public var rectifiedDocument: PlatformImage?
    public var rectifiedDocumentText: String? // Non-published state to hold text for saving
    @Published public var showingDocumentView: Bool = false
    @Published public var selectedPurposes: Set<String> = []
    @Published public var selectedResults: Set<IntelligenceResult> = []
    @Published public var sessionTitle: String? // Explicit user-selected title
    
    // Map Selection
    @Published public var placeCandidates: [EnrichmentData] = []
    @Published public var selectedPlace: EnrichmentData?
    @Published public var showingPlaceSelection: Bool = false
    
    // Renaming
    @Published public var renamingPlace: EnrichmentData?
    @Published public var newPlaceTitle: String = ""
    
    public func startRenaming(_ place: EnrichmentData) {
        self.renamingPlace = place
        self.newPlaceTitle = place.title ?? ""
    }
    
    public func updatePlaceTitle(for placeID: String, with newTitle: String) {
        // Helper to update a single enrichment instance
        func updatedEnrichment(_ original: EnrichmentData) -> EnrichmentData {
            var newContext = original.placeContext
            // Since PlaceContext properties are also let, we must recreate it if it exists, or create a new one
            let updatedPlaceContext: PlaceContext
            if let existing = newContext {
                updatedPlaceContext = PlaceContext(
                    name: newTitle,
                    categories: existing.categories,
                    placeID: existing.placeID,
                    address: existing.address,
                    rating: existing.rating,
                    isOpen: existing.isOpen,
                    latitude: existing.latitude,
                    longitude: existing.longitude,
                    priceLevel: existing.priceLevel,
                    phoneNumber: existing.phoneNumber,
                    website: existing.website,
                    photos: existing.photos,
                    tips: existing.tips
                )
            } else {
                updatedPlaceContext = PlaceContext(name: newTitle)
            }
            
            return EnrichmentData(
                title: newTitle,
                descriptionText: original.descriptionText,
                image: original.image,
                categories: original.categories,
                styleTags: original.styleTags,
                location: original.location,
                price: original.price,
                rating: original.rating,
                questions: original.questions,
                webContext: original.webContext,
                documentContext: original.documentContext,
                placeContext: updatedPlaceContext,
                qrContext: original.qrContext
            )
        }

        // Update candidates
        if let index = placeCandidates.firstIndex(where: { $0.id == placeID }) {
            placeCandidates[index] = updatedEnrichment(placeCandidates[index])
        }
        
        // Update selection if it matches
        if selectedPlace?.id == placeID, let current = selectedPlace {
            selectedPlace = updatedEnrichment(current)
        }
    }

    
    // Capture Location & Context
    public var currentCaptureCoordinate: CLLocationCoordinate2D?
    public var currentCapturePlaceID: String?
    private var capturedMediaLocation: CLLocation? // Overrides live location if set (e.g. from Video metadata)
    private var capturedMediaDate: Date? // Overrides creation date if set (from Media metadata)
    
    public var sortedResults: [IntelligenceResult] {
        results.sorted { $0.sortPriority < $1.sortPriority }
    }

    // Photo picker selection (for processing a chosen photo)
    @Published public var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            if let _ = selectedPhotoItem {
                processSelectedPhoto()
            }
        }
    }

    // MARK: - Internal State
    @Published public var activeObservation: VNInstanceMaskObservation?
    public var lastCaptureTime: Date?

    @Published public var cameraManager = CameraManager()
    @Published public var currentOrientation: CGImagePropertyOrientation = .up
    private var processor = IntelligenceProcessor()
    private var linkGenerator: DiverLinkGenerator?
    private let webViewService = WebViewLinkEnrichmentService() // New Service
    private var currentAnalysisTask: Task<Void, Never>?
    @Published public var isAnalyzing = false
    @Published public var isSavingDocument = false
    
    // Error Handling
    @Published public var showingSaveError = false
    @Published public var saveErrorMessage: String?
    @Published public var isSaving = false
    
    public init(linkGenerator: DiverLinkGenerator? = nil) {
        if let linkGenerator {
            self.linkGenerator = linkGenerator
        } else {
            setupDiverLinkGenerator()
        }
    }
    
    // Off-main helper to process a frame safely without sending main-actor state
    // Off-main helper to process a frame safely without sending main-actor state
    nonisolated(nonsending)
    private func processFrameOffMain(_ pixelBuffer: UnsafeSendable<CVPixelBuffer>, orientation: CGImagePropertyOrientation, mode: IntelligenceProcessor.AnalysisMode) async -> ([IntelligenceResult], CGRect?)? {
        // Create a local processor to avoid sending the main-actor-isolated `self.processor` across actors
        let localProcessor = IntelligenceProcessor()
        guard let results = try? await localProcessor.process(frame: pixelBuffer.value, orientation: orientation, mode: mode) else { return nil }
        
        var bounds: CGRect?
        if let sifted = results.first(where: { if case .siftedSubject = $0 { return true } else { return false } }),
           case .siftedSubject(let obs, _) = sifted {
             // Calculate bounds OFF-MAIN here
             bounds = localProcessor.calculateBounds(from: obs)
        }
        
        return (results, bounds)
    }
    
    // MARK: - Reprocessing
    public func checkPendingReprocess() {
        guard let context = Services.shared.pendingReprocessContext else { return }
        
        print("🔄 VI ViewModel: Found pending reprocess context for session \(context.sessionID)")
        
        // 1. Load Image
        // 1. Load Image
        #if canImport(UIKit)
        if let image = UIImage(data: context.imageData) {
            self.capturedImage = image
            self.siftedImage = image 
        } else {
            // Fallback: Try CIImage or CGImageSource debug
            print("❌ VI ViewModel: UIImage(data:) failed for session \(context.sessionID). Size: \(context.imageData.count) bytes. Trying fallbacks...")
            
            // Attempt CGImageSource directly for robustness
            if let source = CGImageSourceCreateWithData(context.imageData as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                self.capturedImage = image
                self.siftedImage = image
                print("✅ VI ViewModel: Recovered image via CGImageSource.")
            } else if let ciImage = CIImage(data: context.imageData) {
                 let context = CIContext()
                 if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                     self.capturedImage = UIImage(cgImage: cgImage)
                     self.siftedImage = self.capturedImage
                     print("✅ VI ViewModel: Recovered image via CIImage.")
                 } else {
                     print("❌ VI ViewModel: CIImage created but CGImage failed.")
                 }
            } else {
                 print("❌ VI ViewModel: All image recovery attempts failed. Data header: \(context.imageData.prefix(20).map { String(format: "%02hhx", $0) }.joined())")
            }
        }
        #endif
        
        // 2. Set Session & Metadata
        self.activeSessionID = context.sessionID
        self.currentCapturePlaceID = context.placeID
        if let loc = context.location {
            let parts = loc.split(separator: ",")
            if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                self.currentCaptureCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        
        // 3. Pre-fill Place Candidate if we have ID/Name
        // COMMENTED OUT: User request to CLEAR previous selection on reprocess to allow fresh search/detection
        /*
        if let pid = context.placeID, let name = context.placeName {
            // Create a dummy enrichment data to represent current place
            let placeContext = PlaceContext(name: name, categories: [], placeID: pid, address: nil, latitude: self.currentCaptureCoordinate?.latitude, longitude: self.currentCaptureCoordinate?.longitude)
            let enrichment = EnrichmentData(title: name, descriptionText: nil, categories: [], styleTags: [], location: context.location, price: nil, rating: nil, questions: [], placeContext: placeContext)
            self.selectedPlace = enrichment
        }
        */
        self.selectedPlace = nil // Explicitly clear to ensure fresh search priority
        
        // 4. Enter Review Mode
        self.isReviewing = true
        
        // 5. Trigger Analysis immediately
        if let image = self.capturedImage {
            self.analyzeReprocessImage(image)
        }
        
        // 6. Clear context so we don't loop
        Services.shared.pendingReprocessContext = nil
    }
    
    public func analyzeReprocessImage(_ image: PlatformImage) {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        #endif
        
        self.isAnalyzing = true
        
        Task(priority: .utility) {
            do {
                // Saved payloads are normalized to .up
                let newResults = try await self.processor.process(image: cgImage, orientation: .up, mode: .fullAnalysis)
                
                await MainActor.run {
                    self.results = newResults
                    // self.capturedImage is already set
                    
                    // Sifted logic
                    if let sifted = newResults.first(where: { if case .siftedSubject = $0 { return true }; return false }),
                       case .siftedSubject(let observation, _) = sifted {
                        Task {
                            if let (sImage, sBounds) = await self.extractSiftedImage(
                                observation: UnsafeSendable(value: observation),
                                frame: UnsafeSendable(value: cgImage),
                                orientation: .up
                            ) {
                                await MainActor.run {
                                    self.siftedImage = sImage
                                    self.siftedBoundingBox = sBounds
                                }
                            }
                        }
                    }
                    
                    self.isReviewing = true // Ensure we are in review mode
                    self.isAnalyzing = false
                }
                
                // Verification
                Task {
                    for await result in self.processor.verify(initialResults: newResults, image: cgImage) {
                        await MainActor.run {
                            if !self.results.contains(result) {
                                withAnimation {
                                    self.results.append(result)
                                }
                            }
                        }
                    }
                }
                
                // NEW: Automatically trigger "Analyze Context" after reprocessing
                // Wait for verification loop to finish kicking off results, then trigger context
                Task {
                     // Add a small delay to allow UI to settle?
                     try? await Task.sleep(nanoseconds: 500_000_000)
                     await MainActor.run {
                        print("🤖 Reprocessing: Auto-triggering Context Analysis...")
                        Task {
                             await self.regenerateContextSuggestions(for: self.selectedPlace)
                        }
                    }
                }
                
            } catch {
                print("❌ Reprocess Analysis Failed: \(error)")
                await MainActor.run { self.isAnalyzing = false }
            }
        }
    }

    // MARK: - Setup
    
    private func setupDiverLinkGenerator() {
        if let queueURL = AppGroupContainer.queueDirectoryURL(),
           let secretString = KeychainService(service: KeychainService.ServiceIdentifier.diver, accessGroup: AppGroupConfig.default.keychainAccessGroup).retrieveString(key: KeychainService.Keys.diverLinkSecret),
           let secret = Data(base64Encoded: secretString) {
            do {
                let store = try DiverQueueStore(directoryURL: queueURL)
                self.linkGenerator = DiverLinkGenerator(store: store, secret: secret)
                print("✅ Visual Intelligence VM: Data Link Established")
            } catch {
                print("❌ Visual Intelligence VM: Failed to init QueueStore: \(error)")
            }
        }
    }
    
    // Live loop definition
    private var isProcessingFrame = false
    private var lastProcessingTime: Date = .distantPast
    private let processingInterval: TimeInterval = 0.5 // 500ms between live analysis passes

    public func setupCameraBridge() {
        // Check for reprocssing job
        checkPendingReprocess()
        
        // Start the session when bridging
        cameraManager.startSession()
        
        // Use a detached task for the throttling logic to avoid blocking the camera queue or main thread
        cameraManager.onFrameCaptured = { [weak self] pixelBuffer in
            guard let self = self else { return }
            
            // Check throttling safely without hopping to main actor
            let now = Date()
            if now.timeIntervalSince(self.lastProcessingTime) < self.processingInterval {
                return
            }
            
            // Mark as processing (using atomic or actor isolation would be better, but we'll use a local check for now)
            if self.isProcessingFrame { return }
            self.isProcessingFrame = true
            self.lastProcessingTime = now
            
            Task {
                // Check pause state to respect user request ("pause sifting until completed")
                let shouldPause = await MainActor.run { self.isAnalyzing || self.isReviewing }
                if shouldPause {
                    self.isProcessingFrame = false
                    return
                }

                // 3. Process off the main actor without sending non-Sendable values directly
                let sendableBuffer = UnsafeSendable(value: pixelBuffer)
                let orientation = await MainActor.run { self.currentOrientation }
                
                // Live Feed: Enable sifting ONLY (mode: .liveSifting)
                // Results + Pre-calculated Bounds
                let processingOutput = await self.processFrameOffMain(sendableBuffer, orientation: orientation, mode: .liveSifting)

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if let (newResults, newBounds) = processingOutput {
                        // Only update 'results' (Metadata) if we are NOT reviewing.
                        // If reviewing, we want the pills to stay static (showing the captured data).
                        if !self.isReviewing {
                            self.results = newResults
                        }

                        // Extract observation if present for state tracking (Live Highlighting)
                        // We DO update this even in review mode, so the background "Live View" still feels alive/highlighted
                        if let sifted = newResults.first(where: { if case .siftedSubject = $0 { return true } else { return false } }),
                           case .siftedSubject(let obs, _) = sifted {
                            self.activeObservation = obs
                            self.siftedBoundingBox = newBounds // Use off-main calculated bounds
                        } else {
                            self.activeObservation = nil
                            self.siftedBoundingBox = nil
                        }
                    }
                    self.isProcessingFrame = false
                }
            }
        }

            cameraManager.onPhotoCaptured = { [weak self] imageData in
                // Cancel previous analysis to prevent race conditions
                self?.currentAnalysisTask?.cancel()
                
                self?.currentAnalysisTask = Task(priority: .utility) { @MainActor [weak self] in
                    #if canImport(UIKit)
                    let image = UIImage(data: imageData)
                    #elseif canImport(AppKit)
                    let image = NSImage(data: imageData)
                    #else
                    let image: PlatformImage? = nil
                    #endif
                    
                    guard let self = self else { return }
                    
                    // Prioritize pending result (e.g. valid QR code from handleCapture) if image fails
                    if image == nil {
                         print("⚠️ Camera: Captured image data is invlid/empty")
                         if let pending = self.pendingCaptureResult {
                             print("🚀 Express Capture: Saving pending result despite image fail...")
                             self.results = [pending]
                             self.pendingCaptureResult = nil
                             self.commitReviewSave() // This might fail if commitReviewSave requires image?
                         }
                         return
                    }
                    
                    print("📸 Camera: Photo captured, analyzing full frame using subject priority...")
                    self.capturedImage = image
                    if let img = image {
                        self.sessionImages.append(img)
                        // Save to Photo Library as Backup
                        self.saveImageToPhotoLibrary(img)
                    }
                    
                    #if canImport(UIKit)
                    let cgImage = image?.cgImage
                    #elseif canImport(AppKit)
                    let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    #else
                    let cgImage: CGImage? = nil
                    #endif
                    
                    if let cgImage = cgImage {
                         // Capture Mode: Full Analysis (mode: .fullAnalysis)
                         // We run Barcode + Text + Classification AND Check for Sifted ROI
                    do {
                        let fullResults = try await self.processor.process(image: cgImage, orientation: self.currentOrientation, mode: .fullAnalysis)
                        
                        // Override the results with the HIGH FIDELITY capture results
                        var resultsWithPurpose = fullResults
                        
                        // NEW: Concurrent Enrichment Pipeline
                        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                            print("🚀 Enrichment Pipeline: Starting Concurrent Enrichment...")
                            
                            // Capture history on MainActor before awaiting
                            let currentHistory = self.accumulatedContexts
                            
                            // Call detached enrichment
                            // Call detached enrichment
                            let (enriched, stepSummary, candidates) = await self.enrichContext(from: fullResults, accumulatedContext: currentHistory)
                            
                            // Home/Work Enrichment
                            var finalCandidates = candidates
                            if let contactService = Services.shared.contactService {
                                let home = try? await contactService.getHomeLocation()
                                let work = try? await contactService.getWorkLocation()
                                
                                // Check if we have a valid current location to compare distance to
                                // Check if we have a valid current location to compare distance to
                                var currentLocation: CLLocation? = self.capturedMediaLocation
                                
                                if currentLocation == nil, let locService = Services.shared.locationService {
                                     currentLocation = await locService.getCurrentLocation()
                                }
                                
                                if let loc = currentLocation {
                                     await MainActor.run {
                                         self.currentCaptureCoordinate = loc.coordinate
                                     }
                                }

                                if let current = currentLocation {
                                    var personalPlaces: [EnrichmentData] = []
                                    
                                    // Threshold: 150 meters
                                    if let homeLoc = home, homeLoc.distance(from: current) < 150 {
                                        personalPlaces.append(EnrichmentData(
                                            title: "Home",
                                            descriptionText: "Your Personal CustomContext",
                                            categories: ["Personal", "Home"],
                                            location: "Home",
                                            placeContext: PlaceContext(name: "Home", categories: ["Personal"], latitude: homeLoc.coordinate.latitude, longitude: homeLoc.coordinate.longitude)
                                        ))
                                    }
                                    
                                    if let workLoc = work, workLoc.distance(from: current) < 150 {
                                         personalPlaces.append(EnrichmentData(
                                            title: "Work",
                                            descriptionText: "Your Workplace",
                                            categories: ["Personal", "Work"],
                                            location: "Work",
                                            placeContext: PlaceContext(name: "Work", categories: ["Personal"], latitude: workLoc.coordinate.latitude, longitude: workLoc.coordinate.longitude)
                                        ))
                                    }
                                    
                                    if !personalPlaces.isEmpty {
                                        finalCandidates.insert(contentsOf: personalPlaces, at: 0)
                                        await MainActor.run {
                                            if let first = personalPlaces.first {
                                                self.selectPlace(first)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // 3. Smart Default Selection Priority:
                            // 1. User Selected (Manual) - Handled by UI persistence or explicit selection
                            // 2. Detected Place (Visual Match)
                            // 3. First Suggested (Proximity/Home)

                            var candidatesToUpdate = finalCandidates
                            
                            // Check for Visual Text Match
                            // We look for candidate titles in the captured text
                            let capturedText = fullResults.compactMap { result -> String? in
                                if case .text(let text, _) = result { return text }
                                return nil
                            }.joined(separator: " ").lowercased()
                            
                            var bestMatch: EnrichmentData?
                            if !capturedText.isEmpty {
                                for candidate in candidatesToUpdate {
                                    if let title = candidate.title?.lowercased(), capturedText.contains(title) {
                                        print("🎯 Visual Intelligence: Found visual text match for place: \(title)")
                                        bestMatch = candidate
                                        break
                                    }
                                }
                            }
                            
                            await MainActor.run {
                                // Preserve existing selection if active
                                if let existingSelection = self.selectedPlace {
                                    if !candidatesToUpdate.contains(where: { $0.title == existingSelection.title }) {
                                        candidatesToUpdate.insert(existingSelection, at: 0)
                                    }
                                }
                                
                                self.placeCandidates = candidatesToUpdate
                                
                                if self.selectedPlace == nil {
                                     // Priority: Visual Match -> First Candidate (Home/Proximity)
                                     self.selectedPlace = bestMatch ?? candidatesToUpdate.first
                                }
                            }
                            
                            // Update MainActor state with new summary
                            if let summary = stepSummary {
                                self.accumulatedContexts.append("Capture \(self.accumulatedContexts.count + 1): " + summary)
                            }
                            
                            // Merge enriched items (replacing base items if needed)
                            // We replace .qr/.text with .richWeb if found
                            // Merge enriched items (replacing base items if needed)
                            // We replace .qr/.text with .richWeb if found
                            var finalResults: [IntelligenceResult] = []
                            
                            // Check if enrichment produced a rich web result
                            let hasRichWeb = enriched.contains { if case .richWeb = $0 { return true }; return false }
                            
                            // First, add all non-obsolete results
                            for result in resultsWithPurpose {
                                if case .qr = result, hasRichWeb {
                                    continue // Skip QR if we have rich web
                                }
                                if case .text = result, hasRichWeb {
                                     continue // Skip Text if we have rich web (assumption: text was the URL source)
                                }
                                finalResults.append(result)
                            }
                            
                            // Append new enriched results
                            finalResults.append(contentsOf: enriched)
                            resultsWithPurpose = finalResults
                        }
                        
                        // Merge pending result (e.g. valid QR code that triggered the capture)
                        var shouldAutoSave = false
                        if let pending = self.pendingCaptureResult {
                            resultsWithPurpose.insert(pending, at: 0)
                            self.pendingCaptureResult = nil
                            shouldAutoSave = true
                        }
                        
                        // Multi-Photo Merge Logic
                        if self.isReviewing {
                            let existing = self.results
                            // De-duplicate based on title + subtitle
                            let newUnique = resultsWithPurpose.filter { newResult in
                                !existing.contains(where: { $0.title == newResult.title && $0.subtitle == newResult.subtitle })
                            }
                            self.results = existing + newUnique
                            print("✅ Multi-Photo: Merged \(newUnique.count) new results. Total: \(self.results.count)")
                        } else {
                            self.results = resultsWithPurpose
                        }
                        
                        print("✅ Analysis Complete: Found \(fullResults.count) results")
                        
                        if shouldAutoSave {
                            print("🚀 Express Capture: Auto-saving...")
                            self.commitReviewSave()
                        }
                        
                        // Trigger Background Verification (Verification Round 2)
                        // Note: We need a CGImage for verification. capturedImage is a PlatformImage.
                        #if canImport(UIKit)
                        let cgImg = self.capturedImage?.cgImage
                        #elseif canImport(AppKit)
                        let cgImg = self.capturedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                        #endif
                        
                        if let cgImage = cgImg {
                            print("🔍 Starting Background Verification (HandleCapture)...")
                            Task {
                                for await result in self.processor.verify(initialResults: self.results, image: cgImage) {
                                    await MainActor.run {
                                        if !self.results.contains(result) {
                                             withAnimation {
                                                 self.results.append(result)
                                             }
                                             #if os(iOS)
                                             let generator = UIImpactFeedbackGenerator(style: .soft)
                                             generator.impactOccurred()
                                             #endif
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        print("❌ Analysis Failed: \(error)")
                    }
                }
                
                self.isAnalyzing = false
                // isReviewing is already true
            }
        }
    }
    
    public func processSelectedPhoto() {
        guard let item = selectedPhotoItem else { return }
        
        print("📸 Processing selected photo...")
        
        // Reset state for new selection (always new session for new photo selection)
        self.activeSessionID = UUID().uuidString
        self.sessionImages = []
        self.results = []
        self.accumulatedContexts = []
        self.siftedBoundingBox = nil
        self.capturedImage = nil
        self.isReviewing = true // Switch to review mode immediately to show loading state
        self.activeObservation = nil
        
        Task {
            do {
                var finalCGImage: CGImage?
                var finalImage: PlatformImage?
                
                // 1. Try Video first (Safe URL loading)
                if let movie = try? await item.loadTransferable(type: Movie.self) {
                    print("🎥 Processing as Video/Movie (URL-based)...")
                    if let (cgImage, location, date) = await processVideoData(movie.url) {
                        finalCGImage = cgImage
                        await MainActor.run {
                            if let loc = location {
                                 self.capturedMediaLocation = loc
                                 print("📍 Video Location captured: \(loc)")
                            }
                            if let d = date {
                                self.capturedMediaDate = d
                                print("📅 Video Date captured: \(d)")
                            }
                        }
                        
                        #if canImport(UIKit)
                        finalImage = UIImage(cgImage: cgImage)
                        #elseif canImport(AppKit)
                        finalImage = NSImage(cgImage: cgImage, size: .zero)
                        #endif
                        print("✅ Extracted Best Frame from Video URL")
                    }
                }
                
                // 2. Fallback to Data (for Images) if Video failed or wasn't a video
                if finalCGImage == nil {
                     // CAUTION: large videos might still crash here if they failed the .movie check but succeed as .data
                     // But typically PhotosPicker filters items.
                     guard let data = try await item.loadTransferable(type: Data.self) else { return }
                     
                     #if canImport(UIKit)
                     // Try as Image
                     if let image = UIImage(data: data) {
                         finalImage = image
                         finalCGImage = image.cgImage
                         
                         // Extract Image Creation Date
                         if let source = CGImageSourceCreateWithData(data as CFData, nil),
                            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                             var dateString: String?
                             if let exif = props["{Exif}"] as? [String: Any] {
                                 dateString = exif["DateTimeOriginal"] as? String
                             }
                             if dateString == nil, let tiff = props["{TIFF}"] as? [String: Any] {
                                 dateString = tiff["DateTime"] as? String
                             }
                             
                             if let ds = dateString {
                                 let formatter = DateFormatter()
                                 formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                 if let date = formatter.date(from: ds) {
                                     await MainActor.run {
                                         self.capturedMediaDate = date
                                         print("📅 Image Date captured: \(date)")
                                     }
                                 }
                             }
                         }
                     }
                     #elseif canImport(AppKit)
                     if let image = NSImage(data: data) {
                         finalImage = image
                         finalCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                     }
                     #endif
                     
                     // 3. Last Resort Video (Data-based) - only small videos might survive this
                     if finalCGImage == nil {
                         print("⚠️ Video URL load failed. Attempting Data fallback (risky)...")
                         if let (cgImage, location, date) = await processVideoData(data) {
                             finalCGImage = cgImage
                             await MainActor.run {
                                 if let loc = location { self.capturedMediaLocation = loc }
                                 if let d = date { self.capturedMediaDate = d }
                             }
                             #if canImport(UIKit)
                             finalImage = UIImage(cgImage: cgImage)
                             #endif
                         }
                     }
                }
                
                guard let cgImage = finalCGImage else { return }
                let image = finalImage 
                
                await MainActor.run { self.isAnalyzing = true }
                    
                    // Analyze for interactive results
                    // For photo library, we usually assume .up logic unless meta says otherwise
                    let newResults = try await self.processor.process(image: cgImage, orientation: .up, mode: .fullAnalysis)
                    
                    await MainActor.run {
                        print("🖼 Photo Picker: Analysis complete, transitioning to Reviewing state")
                        self.results = newResults
                        self.capturedImage = image
                        
                        // Extract sifted image if found
                        if let sifted = newResults.first(where: { if case .siftedSubject = $0 { return true }; return false }),
                           case .siftedSubject(let observation, _) = sifted {
                            Task {
                                if let (sImage, sBounds) = await self.extractSiftedImage(
                                    observation: UnsafeSendable(value: observation),
                                    frame: UnsafeSendable(value: cgImage), // Overload used for CGImage
                                    orientation: .up
                                ) {
                                    await MainActor.run {
                                        self.siftedImage = sImage
                                        self.siftedBoundingBox = sBounds
                                    }
                                }
                            }
                        }
                        
                        self.isReviewing = true
                    }
                    
                    // Trigger Background Verification
                    print("🔍 Starting Background Verification...")
                    Task {
                        for await result in self.processor.verify(initialResults: newResults, image: cgImage) {
                            await MainActor.run {
                                if !self.results.contains(result) {
                                    withAnimation {
                                        self.results.append(result)
                                    }
                                    #if os(iOS)
                                    let generator = UIImpactFeedbackGenerator(style: .soft)
                                    generator.impactOccurred()
                                    #endif
                                }
                            }
                        }
                    }
            } catch {
                print("❌ Failed to process selected photo: \(error)")
                await MainActor.run {
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    // MARK: - Background Processing
    
    public func analyzeStaticImage(_ image: PlatformImage) {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        #endif
        analyzeStaticImage(cgImage: cgImage)
    }

    private func analyzeStaticImage(cgImage: CGImage) {
        Task.detached(priority: .userInitiated) {
             do {
                 let request = VNGenerateForegroundInstanceMaskRequest()
                 let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                 try handler.perform([request])
                 
                 if let result = request.results?.first {
                    if let (sImage, sBounds) = await self.extractSiftedImage(
                        observation: UnsafeSendable(value: result),
                        frame: UnsafeSendable(value: cgImage),
                        orientation: .up
                    ) {
                        await MainActor.run { [weak self] in
                            self?.siftedImage = sImage
                            self?.siftedBoundingBox = sBounds
                        }
                    }
                }
             } catch {
                 print("❌ Generic static analysis failed: \(error)")
             }
        }
    }
    
    nonisolated(nonsending) private func extractSiftedImage(
        observation: UnsafeSendable<VNInstanceMaskObservation>, 
        frame: UnsafeSendable<CVPixelBuffer>,
        orientation: CGImagePropertyOrientation
    ) async -> (PlatformImage, CGRect)? {
        guard let result = try? await performExtraction(observation: observation.value, handler: VNImageRequestHandler(cvPixelBuffer: frame.value, orientation: orientation, options: [:]), orientation: orientation) else { return nil }
        return result
    }

    nonisolated(nonsending) private func extractSiftedImage(
        observation: UnsafeSendable<VNInstanceMaskObservation>, 
        frame: UnsafeSendable<CGImage>,
        orientation: CGImagePropertyOrientation
    ) async -> (PlatformImage, CGRect)? {
        guard let result = try? await performExtraction(observation: observation.value, handler: VNImageRequestHandler(cgImage: frame.value, orientation: orientation, options: [:]), orientation: orientation) else { return nil }
        return result
    }

    nonisolated(nonsending) private func performExtraction(
        observation: VNInstanceMaskObservation,
        handler: VNImageRequestHandler,
        orientation: CGImagePropertyOrientation
    ) async throws -> (PlatformImage, CGRect)? {
        // 1. Generate the cropped masked image
        let maskBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )
        
        // 2. Calculate the bounding box from the instanceMask buffer
        // This is robust across OS versions that don't expose observation.boundingBox
        let bounds = calculateBounds(from: observation)
        
        let ciImage = CIImage(cvPixelBuffer: maskBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            #if canImport(UIKit)
            // Use default orientation for the sticker
            let uiImage = UIImage(cgImage: cgImage)
            return (uiImage, bounds)
            #elseif canImport(AppKit)
            return (NSImage(cgImage: cgImage, size: .zero), bounds)
            #endif
        }
        return nil
    }

    nonisolated private func calculateBounds(from observation: VNInstanceMaskObservation) -> CGRect {
        let maskBuffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var found = false
        
        // Rapid scan for non-zero pixels (instance indices)
        for y in 0..<height {
            let row = buffer + (y * bytesPerRow)
            for x in 0..<width {
                if row[x] != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    found = true
                }
            }
        }
        
        if !found {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        // Convert to normalized coordinates (0.0 - 1.0)
        // Vision origin is bottom-left, but the buffer Y is top-down
        let normalizedMinX = CGFloat(minX) / CGFloat(width)
        let normalizedMaxX = CGFloat(maxX) / CGFloat(width)
        let normalizedMinY = 1.0 - (CGFloat(maxY) / CGFloat(height))
        let normalizedMaxY = 1.0 - (CGFloat(minY) / CGFloat(height))
        
        return CGRect(
            x: normalizedMinX,
            y: normalizedMinY,
            width: normalizedMaxX - normalizedMinX,
            height: normalizedMaxY - normalizedMinY
        )
    }

    #if canImport(UIKit)
    @MainActor
    private func uiImageOrientation(from orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    #endif
    
    
    // MARK: - Photo Library Saving
    
    private func saveImageToPhotoLibrary(_ image: PlatformImage) {
        #if os(iOS)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("⚠️ Photo Library Saving denied or restricted")
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    print("✅ Saved captured image to Photo Library")
                } else {
                    print("❌ Failed to save image to Photo Library: \(String(describing: error))")
                }
            }
        }
        #endif
    }
    
    // MARK: - Logic
    
    private func checkForExpressCapture(_ newResults: [IntelligenceResult]) {
        if let qr = newResults.first(where: { result in
            if case .qr = result { return true }
            return false
        }) {
            if lastCaptureTime == nil || Date().timeIntervalSince(lastCaptureTime!) > 2.0 {
                handleCapture(result: qr)
                lastCaptureTime = Date()
            }
        }
    }
    
    private var pendingCaptureResult: IntelligenceResult?

    public func handleCapture(result: IntelligenceResult? = nil) {
        // 1. Immediate UI Response
        Task { @MainActor in
            self.isReviewing = true
            self.isAnalyzing = true
            self.pendingCaptureResult = result // Store for processing
            // Clear previous state for "Skeleton" mode if this is a fresh start, otherwise we might keep them? 
            // Actually, if we hit X, we clear. If we capture, we want to see review.
            // If we are already reviewing and hit +, we don't clear.
            if !self.isReviewing {
                self.results = []
                self.sessionImages = []
                self.accumulatedContexts = []
                self.capturedImage = nil
            }
            
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            #endif
        }
        
        // 2. Filter actionable intelligence if needed (preserving existing logic)
        // ... (this logic is less relevant now as we force capture, but keeping for safekeeping)
        
        // 3. Trigger Photo Capture
        print("📸 Capturing photo for review view feedback...")
        cameraManager.capturePhoto()
    }
    
    public func reCapture(preservingSessionID: Bool = false) {
        print("🔄 Re-capturing from live feed... (Preserving Session: \(preservingSessionID))")
        
        let sessionIDToUse = preservingSessionID ? self.activeSessionID : UUID().uuidString
        
        Task { @MainActor in
            self.activeSessionID = sessionIDToUse
            self.sessionImages = []
            self.results = []
            self.accumulatedContexts = []
            self.siftedBoundingBox = nil
            self.capturedImage = nil
            self.isReviewing = false
            self.handleCapture()
        }
    }
    public func startNewSession() {
        self.reCapture(preservingSessionID: false)
    }

    public func commitReviewSave() {
        if isSaving { return }
        isSaving = true
        
        print("💾 commitReviewSave: Crystalizing Logic...")
        
        guard let queueStore = linkGenerator?.store else {
            print("❌ QueueStore not available")
            Task { @MainActor in
                self.saveErrorMessage = "Storage unavailable (QueueStore). Please restart the app."
                self.showingSaveError = true
                self.isSaving = false
            }
            return
        }
        
        // Correct approach: Capture needed data from MainActor first
        // If selection is made, only save selected. Otherwise save all (or maybe empty? User choice implies filtering).
        // Let's assume if ANY are selected, we filter. If NONE are selected, we save ALL (default behavior).
        let currentResults: [IntelligenceResult] = self.selectedResults.isEmpty ? self.results : self.results.filter { self.selectedResults.contains($0) }
        
        let purposes = self.selectedPurposes
        var imageToSave: PlatformImage? = nil
        #if canImport(UIKit)
        imageToSave = capturedImage
        #elseif canImport(AppKit)
        imageToSave = capturedImage
        #endif
        
        // Capture sifted image from VM state
        var siftedImg: PlatformImage? = nil
        #if canImport(UIKit)
        siftedImg = self.siftedImage
        #elseif canImport(AppKit)
        siftedImg = self.siftedImage
        #endif
        
        let sessionImgs = self.sessionImages
        let sessionID = self.activeSessionID
        
        if imageToSave == nil && results.isEmpty {
             self.isSaving = false
             return
        }
        
        let capturePlaceID = self.currentCapturePlaceID
        let captureCoordinate = self.currentCaptureCoordinate
        let selectedPlaceTitle = self.selectedPlace?.title
        
        // Determine intelligent title priority:
        // 1. Explicit Session Title (User Tapped Chip)
        // 2. Selected Intent (e.g. "Reading Menu") - EXCLUDING "At: Place" location tags
        // 3. Verified Result Title (e.g. "Starbucks")
        // 4. Original Place/Web Title
        // 5. Fallback
        
        let validIntent = purposes.first { !$0.starts(with: "At: ") }
        
        // Use the selected intent as the primary title if it exists, otherwise fall back to enriched title
        let calculatedTitle = self.sessionTitle ?? validIntent ?? self.results.first?.title ?? "Visual Capture"
        
        // Ensure the calculated title is actually used or stored
        if self.sessionTitle == nil {
            self.sessionTitle = calculatedTitle
        }
        
        Task.detached(priority: .userInitiated) {
            #if canImport(UIKit)
            let capturedData = imageToSave?.jpegData(compressionQuality: 0.8)
            let siftedData = siftedImg?.pngData()
            let attachmentData = sessionImgs.compactMap { $0.jpegData(compressionQuality: 0.8) }
            #elseif canImport(AppKit)
            let capturedData = imageToSave?.tiffRepresentation
            let siftedData = siftedImg?.tiffRepresentation
            let attachmentData = sessionImgs.compactMap { $0.tiffRepresentation }
            #else
            let capturedData: Data? = nil
            let siftedData: Data? = nil
            let attachmentData: [Data]? = nil
            #endif
            
            // Save Context Image to Disk (Temp) to pass as URL
            var contextImageURL: URL?
            if let data = capturedData, let queueDir = AppGroupContainer.queueDirectoryURL() {
                let fileName = "context_\(UUID().uuidString).jpg"
                let fileURL = queueDir.appendingPathComponent(fileName)
                do {
                    try data.write(to: fileURL)
                    contextImageURL = fileURL
                } catch {
                    print("❌ Failed to save context image to shared queue dir: \(error)")
                }
            }
            
            // 2. Create Intelligent Queue Items (Master + Children)
            do {
                let queueItems = DiverQueueItem.items(intelligenceResults: currentResults, capturedImage: capturedData, siftedImage: siftedData, attachments: attachmentData, purposes: purposes, sessionID: sessionID, contextImageURL: contextImageURL, placeID: capturePlaceID, latitude: captureCoordinate?.latitude, longitude: captureCoordinate?.longitude, locationName: selectedPlaceTitle)
                
                for item in queueItems {
                    try queueStore.enqueue(item)
                }
                
                if !queueItems.isEmpty {
                    await MainActor.run {
                        self.isSaving = false // Done
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        #endif
                        NotificationCenter.default.post(name: .diverQueueDidUpdate, object: nil)
                        
                        // Enforce SSOT: Reset VM state so we don't hold onto stale "capturedImage"
                        self.reset()
                    }
                }
            } catch {
                 print("Failed to save capture: \(error)")
                 await MainActor.run {
                     self.isSaving = false
                     self.saveErrorMessage = "Failed to save: \(error.localizedDescription)"
                     self.showingSaveError = true
                 }
            }
        }
    }
    
    #if canImport(UIKit)
    public func saveToPhotoLibrary(image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized || status == .limited {
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, error in
                    if success {
                        DispatchQueue.main.async {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            #endif
                            print("✅ Saved Sifted Object to Photos")
                        }
                    }
                }
            }
        }
    }
    #endif
    
    // MARK: - Document Handling
    
    public func handleDocumentSelection(_ observation: VNRectangleObservation, text: String? = nil) {
        self.rectifiedDocumentText = text
        Task {
            guard let capturedImage = await MainActor.run(body: { self.capturedImage }) else { return }
             // Ensure we have a CGImage and check orientation
            #if canImport(UIKit)
            guard let cgImage = capturedImage.cgImage else { return }
            #elseif canImport(AppKit)
            guard let cgImage = capturedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            #endif
            
            // Offload rectification
            if let cgImage = await performRectification(
                observation: UnsafeSendable(value: observation),
                image: UnsafeSendable(value: cgImage)
            ) {
                await MainActor.run {
                    #if canImport(UIKit)
                    self.rectifiedDocument = UIImage(cgImage: cgImage)
                    #elseif canImport(AppKit)
                    self.rectifiedDocument = NSImage(cgImage: cgImage, size: .zero)
                    #endif
                    self.showingDocumentView = true
                }
            }
        }
    }
    
    nonisolated(nonsending)
    private func performRectification(
        observation: UnsafeSendable<VNRectangleObservation>,
        image: UnsafeSendable<CGImage>
    ) async -> CGImage? {
        let ciImage = CIImage(cgImage: image.value)
        
        // Convert Vision normalized coordinates to Image coordinates
        let width = CGFloat(image.value.width)
        let height = CGFloat(image.value.height)
        
        func scale(_ point: CGPoint) -> CGPoint {
            return CGPoint(x: point.x * width, y: point.y * height)
        }
        
        let bottomLeft = scale(observation.value.bottomLeft)
        let bottomRight = scale(observation.value.bottomRight)
        let topLeft = scale(observation.value.topLeft)
        let topRight = scale(observation.value.topRight)
        
        // Calculate estimated physical dimensions
        let topWidth = hypot(topRight.x - topLeft.x, topRight.y - topLeft.y)
        let bottomWidth = hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y)
        let avgWidth = (topWidth + bottomWidth) / 2.0
        
        let leftHeight = hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y)
        let rightHeight = hypot(topRight.x - bottomRight.x, topRight.y - bottomRight.y)
        let avgHeight = (leftHeight + rightHeight) / 2.0
        
        // Apply CIPerspectiveCorrection
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        
        guard let correctedImage = filter.outputImage else { return nil }
        
        // Scale to correct aspect ratio
        // CIPerspectiveCorrection outputs an image of the size of the input image's extent.
        // We need to scale it to avgWidth x avgHeight
        let inputExtent = ciImage.extent
        let scaleX = avgWidth / inputExtent.width
        let scaleY = avgHeight / inputExtent.height
        
        let scaledImage = correctedImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }
    
    public func saveDocument(title: String? = nil, tags: [String] = []) {
        guard let queueStore = linkGenerator?.store else {
            print("❌ saveDocument: Missing requirements")
            return
        }
        
        // Capture state on MainActor
        let rectified = self.rectifiedDocument
        let captured = self.capturedImage
        let sifted = self.siftedImage
        
        // Prioritize Rectified (Manual Crop) -> Captured (Full Context) -> Sifted
        // User Request: "Analysis on Entire Image" => Prefer Captured over Sifted if no Rectified Document.
        guard let primaryImage = rectified ?? captured ?? sifted else {
            print("❌ saveDocument: No image available to save")
            return
        }
        
        let purposes = self.selectedPurposes
        let text = self.rectifiedDocumentText // Likely nil if not rectified
        isSavingDocument = true
        
        Task.detached(priority: .userInitiated) {
            var mainData: Data?
            var attachments: [Data] = []
            
            #if canImport(UIKit)
            mainData = primaryImage.jpegData(compressionQuality: 0.8)
            // If we are saving the full captured image, attach the sifted crop as context
            if primaryImage == captured, let s = sifted, let sData = s.jpegData(compressionQuality: 0.8) {
                attachments.append(sData)
            }
            #elseif canImport(AppKit)
            mainData = primaryImage.tiffRepresentation
            if primaryImage == captured, let s = sifted, let sData = s.tiffRepresentation {
                attachments.append(sData)
            }
            #endif
            
            guard let data = mainData else {
                await MainActor.run { self.isSavingDocument = false }
                return
            }
            
            let lat = await MainActor.run { self.currentCaptureCoordinate?.latitude }
            let lng = await MainActor.run { self.currentCaptureCoordinate?.longitude }
            let placeID = await MainActor.run { self.currentCapturePlaceID }
            let locationName = await MainActor.run { self.selectedPlace?.title }
            let date = await MainActor.run { self.capturedMediaDate }
            let sessionID = await MainActor.run { self.activeSessionID }

             // User Request: Save captured image to Photo Library
            #if canImport(UIKit)
            if let original = captured as? UIImage {
                await MainActor.run {
                    self.saveToPhotoLibrary(image: original)
                }
            }
            #endif

            let queueItem = DiverQueueItem.from(documentImage: data, title: title, tags: tags, text: text, purposes: purposes, date: date, sessionID: sessionID, placeID: placeID, latitude: lat, longitude: lng, locationName: locationName, attachments: attachments)
            
            do {
                try queueStore.enqueue(queueItem)
                await MainActor.run {
                    self.isSavingDocument = false
                    self.rectifiedDocument = nil
                    // Do NOT clear captured/sifted/results immediately if we want to allow re-save? 
                    // Usually we dismiss the VI view after save.
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    #endif
                    NotificationCenter.default.post(name: .diverQueueDidUpdate, object: nil)
                    print("✅ Document/Capture saved to queue")
                }
            } catch {
                print("❌ Failed to enqueue item: \(error)")
                await MainActor.run { self.isSavingDocument = false }
            }
        }
    }
    
    public func addUserContext(_ text: String) {
        guard !text.isEmpty else { return }
        self.selectedPurposes.insert(text)
    }
    
    public func selectPlace(_ place: EnrichmentData) {
        self.selectedPlace = place
        self.showingPlaceSelection = false
        
        // Update persistent capture location
        if let ctx = place.placeContext {
            if let lat = ctx.latitude, let lng = ctx.longitude {
                self.currentCaptureCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            if let pid = ctx.placeID {
                self.currentCapturePlaceID = pid
            }
        }
        
        // Add place context to purposes
        if let name = place.title {
            let label = "At: \(name)"
            self.selectedPurposes.insert(label)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
        
        // Trigger LLM Context Regeneration
        Task {
            await regenerateContextSuggestions(for: place)
        }
    }
    
    func regenerateContextSuggestions(for place: EnrichmentData?) async {
        // Capture state on MainActor synchronously
        let (contextData, shouldProceed) = await MainActor.run { () -> (EnrichmentData?, Bool) in
            self.isAnalyzing = true
            
            // Clear old suggestions immediately
            self.results.removeAll { if case .purpose = $0 { return true }; return false }
            
            // Gather Visual Context from current results
            let visualLabels = self.results.compactMap { result -> String? in
                if case .semantic(let label, _) = result { return label }
                return nil
            }
            let visualText = self.results.compactMap { result -> String? in
                if case .text(let text, _) = result { return text }
                return nil
            }.joined(separator: " ")
            
            // Gather Rich Context
            let richWebData = self.results.compactMap { result -> String? in
                if case .richWeb(_, let data) = result { return "Web Page: \(data.title ?? "Unknown") - \(data.descriptionText ?? "")" }
                return nil
            }
            let productData = self.results.compactMap { result -> String? in
                if case .product(let code, let type, _) = result { return "Product: \(type) (\(code))" }
                return nil
            }
            let entertainmentData = self.results.compactMap { result -> String? in
                if case .entertainment(let title, let type, _) = result { return "\(type): \(title)" }
                return nil
            }
            let qrData = self.results.compactMap { result -> String? in
                if case .qr(let url) = result { return "QR Code: \(url.absoluteString)" }
                return nil
            }
            
            let allRichData = richWebData + productData + entertainmentData + qrData
            
            // Construct Summary
            var currentStepSummary = ""
            if !allRichData.isEmpty {
                currentStepSummary += "Captured Findings:\n" + allRichData.joined(separator: "\n")
            }
            if !visualLabels.isEmpty {
                if !currentStepSummary.isEmpty { currentStepSummary += "\n" }
                currentStepSummary += "Captured Objects: \(visualLabels.joined(separator: ", "))"
            }
            if !visualText.isEmpty {
                if !currentStepSummary.isEmpty { currentStepSummary += "\n" }
                currentStepSummary += "Captured Text: \(visualText.prefix(1000))..."
            }
            
            // Build History
            var combinedHistory = currentStepSummary
            if !self.accumulatedContexts.isEmpty {
                 combinedHistory += "\n\nPAST CAPTURES:\n" + self.accumulatedContexts.joined(separator: "\n---\n")
            }
    
            // Merge Place Data with Visual Context
            // FIX: Prioritize place title if available, otherwise use visual labels
            let finalTitle = place?.title ?? visualLabels.first?.capitalized
            var finalDesc = (place?.descriptionText ?? "")
            
            if place?.title != nil {
                if !visualLabels.isEmpty {
                    finalDesc = "Captured Objects: \(visualLabels.joined(separator: ", "))\n" + finalDesc
                }
            } else if !visualLabels.isEmpty {
                 // No place, but have objects
                 finalDesc = "Visual Context: " + visualLabels.joined(separator: ", ") + "\n" + finalDesc
            }
            
            finalDesc += "\n\nSESSION HISTORY:\n" + combinedHistory
            
            let explicitLocation = place?.title ?? place?.location
            
            let data = EnrichmentData(
                title: finalTitle,
                descriptionText: finalDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                categories: place?.categories ?? [],
                styleTags: (place?.styleTags ?? []) + visualLabels,
                location: explicitLocation, 
                price: place?.price,
                rating: place?.rating,
                questions: []
            )
            return (data, true)
        }
        
        // Define cleanup immediately for the async scope
        defer { Task { @MainActor in self.isAnalyzing = false } }
        
        guard shouldProceed, let data = contextData else { return }
        
        let localContextService = ContextQuestionService()
        if let (_, statements, _, _) = try? await localContextService.processContext(from: data) {
            await MainActor.run {
                self.results.append(.purpose(statements: statements))
            }
        }
    }
    
    // MARK: - Public Actions
    
    /// Manually triggers a re-evaluation of the context pipeline using the latest available data
    /// (selected place, captured text, etc.)
    public func reprocessPipeline() {
        guard !isAnalyzing else { return }
        
        let targetPlace = selectedPlace ?? placeCandidates.first
        
        Task {
            await regenerateContextSuggestions(for: targetPlace)
        }
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    /// Refines the current context by locking in a user selection and requesting deeper details
    public func refineContext(with text: String) {
        // Lock in the selection
        self.accumulatedContexts.append("User Confirmed: \(text)")
        
        // Trigger regeneration to get new, deeper suggestions based on this confirmation
        reprocessPipeline()
    }
    
    // MARK: - Interaction
    
    public func startRecording() {
        cameraManager.isRecording = true
    }
    
    public func stopRecording() {
        cameraManager.isRecording = false
    }
    
    public func stopCamera() {
        cameraManager.stopSession()
    }
    
    public func updatePeelAmount(_ value: CGFloat) {
        peelAmount = value
    }
    
    public func reset() {
        // Stop any active recording and the session itself
        stopRecording()
        stopCamera() // Stop camera session to prevent background sifting
        
        // Reset UI state
        results = []
        capturedImage = nil
        siftedImage = nil
        siftedBoundingBox = nil
        activeObservation = nil
        peelAmount = 0
        lastCaptureTime = nil
        sessionImages = []
        
        // Reset process state
        isSaving = false
        showingSaveError = false
        saveErrorMessage = nil
        isSavingDocument = false
        capturedMediaLocation = nil
        
        // Reset Selection & Metadata
        selectedPurposes = []
        selectedResults = []
        sessionTitle = nil
        placeCandidates = []
        selectedPlace = nil
        showingPlaceSelection = false
        rectifiedDocument = nil
        rectifiedDocumentText = nil
        showingDocumentView = false
        
        // Reset internal state
        isAnalyzing = false
        isReviewing = false
        
        print("🔄 Visual Intelligence VM: State Reset")
    }
    
    // MARK: - UI Helpers
    
    public func convertBoundingBox(_ box: CGRect, to size: CGSize) -> CGRect {
        // Vision: Origin Bottom-Left, Normalized
        // SwiftUI: Origin Top-Left, Points
        
        // Handle "Right" orientation (Portrait) where width/height might need swapping if buffer differs?
        // Actually, Vision normalized coords are relative to the "Image" logical orientation.
        // If we are portrait, the image is tall.
        
        let w = box.width * size.width
        let h = box.height * size.height
        
        // Flip Y axis: Vision Y is from bottom. SwiftUI Y is from top.
        let x = box.minX * size.width
        let y = (1 - box.maxY) * size.height
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    // MARK: - Enrichment Pipeline
    
    private enum EnrichmentSource {
        case web(URL, EnrichmentData)
        case places([EnrichmentData])
    }
    
    private let contextService = ContextQuestionService()

    private func enrichContext(from initialResults: [IntelligenceResult], accumulatedContext: [String]) async -> ([IntelligenceResult], String?, [EnrichmentData]) {
        if Task.isCancelled { return ([], nil, []) }
        
        // Services
        let webService = self.webViewService
        let locService = Services.shared.locationService
        let fsService = Services.shared.foursquareService
        
        // --- PHASE 1: Data Extraction & Pre-computation ---
        // Identify critical entities that drive enrichment
        
        let qrURL = initialResults.compactMap { res -> URL? in
            if case .qr(let url) = res { return url }
            if case .text(_, let url) = res, url != nil { return url }
            return nil
        }.first
        
        let productEntity = initialResults.compactMap { res -> (String, String)? in
            if case .product(let code, let type, _) = res { return (code, "\(type)") }
            return nil
        }.first
        
        if Task.isCancelled { return ([], nil, []) }

        // --- PHASE 2: Parallel Enrichment ---
        
        async let webEnrichment: EnrichmentSource? = {
            guard let url = qrURL else { return nil }
            if let data = try? await webService.enrich(url: url) {
                return .web(url, data)
            }
            return nil
        }()
        
        async let productEnrichment: EnrichmentSource? = {
            guard let (code, type) = productEntity else { return nil }
            let queryURL = URL(string: "https://www.google.com/search?q=\(code)+\(type)")!
            if let data = try? await webService.enrich(url: queryURL) {
                var pData = data
                pData.categories.append("product")
                pData.styleTags.append(type)
                return .web(queryURL, pData)
            }
            return nil
        }()
        
        async let placeEnrichment: EnrichmentSource? = {
            guard let locService = locService, let location = await locService.getCurrentLocation() else { return nil }
            
            // Refinement: If we have a product or web title, we could technically search for stores matching it?
            // For now, generic nearby search is safest.
            guard let fsService = fsService else { return nil }
            if let candidates = try? await fsService.searchNearby(location: location.coordinate, limit: 50), !candidates.isEmpty {
                return .places(candidates)
            }
            return nil
        }()
        
        // Await all results
        let results = await [webEnrichment, productEnrichment, placeEnrichment]
        
        if Task.isCancelled { return ([], nil, []) }

        // --- PHASE 3: Synthesis & LLM Inference ---
        
        var finalResults: [IntelligenceResult] = []
        var webData: (URL, EnrichmentData)?
        var placeData: EnrichmentData?
        var allCandidates: [EnrichmentData] = []
        
        for res in results {
            switch res {
            case .web(let url, let data):
                webData = (url, data)
                finalResults.append(.richWeb(url: url, data: data))
            case .places(let candidates):
                allCandidates = candidates
                placeData = candidates.first
            case nil: continue
            }
        }
        
        // Aggregation Logic
        var primaryData: EnrichmentData?
        
        if let (_, wData) = webData {
            primaryData = wData
            if let pData = placeData {
               var newDesc = wData.descriptionText ?? ""
               if let placeName = pData.title {
                   newDesc += "\nLocation: \(placeName)"
               }
               primaryData = EnrichmentData(
                   title: wData.title,
                   descriptionText: newDesc,
                   categories: wData.categories + pData.categories,
                   styleTags: wData.styleTags,
                   location: wData.location ?? pData.location,
                   price: wData.price,
                   rating: wData.rating,
                   questions: []
               )
            }
        } else {
            primaryData = placeData
        }
        
        // --- EVENT LOOKUP ---
        var eventContextString: String? = nil
        if let venueName = placeData?.title {
            let encodedVenue = venueName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? venueName
            if let eventURL = URL(string: "https://duckduckgo.com/?q=events+at+\(encodedVenue)&ia=web") {
                 if let eventData = try? await webService.enrich(url: eventURL) {
                     if let desc = eventData.descriptionText, !desc.isEmpty {
                         eventContextString = "Upcoming Events at \(venueName): \(desc)"
                     }
                 }
            }
        }
        
        // Visual Context
        let visualLabels = initialResults.compactMap { res -> String? in
            if case .semantic(let label, _) = res { return label }
            return nil
        }
        let visualText = initialResults.compactMap { res -> String? in
            if case .text(let text, _) = res { return text }
            return nil
        }.joined(separator: " ")
        
        var currentStepSummary = ""
        if !visualLabels.isEmpty {
            currentStepSummary += "Captured Objects: \(visualLabels.joined(separator: ", "))"
        }
        if !visualText.isEmpty {
            if !currentStepSummary.isEmpty { currentStepSummary += "\n" }
            currentStepSummary += "Captured Text: \(visualText.prefix(200))..."
        }
        
        
        var combinedHistory = ""
        if !accumulatedContext.isEmpty {
             combinedHistory = accumulatedContext.joined(separator: "\n---\n")
             if !currentStepSummary.isEmpty {
                 combinedHistory += "\n---\n(Current) " + currentStepSummary
             }
        } else {
             combinedHistory = currentStepSummary
        }
        
        if let pData = primaryData {
            var finalTitle = pData.title
            var finalDesc = (pData.descriptionText ?? "")
            
            if !visualLabels.isEmpty {
                finalTitle = visualLabels.first?.capitalized
                if let placeName = pData.title {
                    finalDesc = "Location: \(placeName)\n" + finalDesc
                }
            }
            
            let findings = finalResults.compactMap { res -> String? in
                switch res {
                case .richWeb(_, let d): return "Web: \(d.title ?? "Link")"
                default: return nil
                }
            }
            if !findings.isEmpty {
                finalDesc += "\n\nFINDINGS:\n" + findings.joined(separator: "\n")
            }
            
            if let events = eventContextString {
                finalDesc += "\n\nEVENTS:\n" + events
            }
            
            finalDesc += "\n\nSESSION HISTORY:\n" + combinedHistory
            
            primaryData = EnrichmentData(
                title: finalTitle,
                descriptionText: finalDesc,
                categories: pData.categories,
                styleTags: pData.styleTags + visualLabels,
                location: pData.location,
                price: pData.price,
                rating: pData.rating,
                questions: []
            )
        } else if !combinedHistory.isEmpty {
             var finalTitle = "Visual Capture"
             if let firstLabel = visualLabels.first { finalTitle = firstLabel.capitalized }
            
            primaryData = EnrichmentData(
                title: finalTitle,
                descriptionText: combinedHistory,
                categories: ["visual"],
                styleTags: visualLabels,
                location: nil,
                price: nil,
                rating: nil,
                questions: []
            )
        }
        
        if Task.isCancelled { return ([], nil, []) }
        
        if let dataToProcess = primaryData {
            let localContextService = ContextQuestionService()
            var addedStatements = false
            
            if let (_, statements, _, _) = try? await localContextService.processContext(from: dataToProcess), !statements.isEmpty {
                finalResults.append(.purpose(statements: statements))
                addedStatements = true
            }
            
            if !addedStatements && !dataToProcess.questions.isEmpty {
                finalResults.append(.purpose(statements: dataToProcess.questions))
            }
        }
        
        if !currentStepSummary.isEmpty {
            let summary = currentStepSummary
            Task { @MainActor in
                Services.shared.dailyContextService?.addContext(summary)
            }
        }

        return (finalResults, currentStepSummary.isEmpty ? nil : currentStepSummary, allCandidates)
    }

    // MARK: - Helpers
    private static func parseISO6709(_ string: String) -> (Double, Double)? {
        // Format: +37.7749-122.4194/
        // Remove trailing slash if present
        let clean = string.replacingOccurrences(of: "/", with: "")
        
        // Find split index (sign of longitude)
        // Skip first char (sign of latitude)
        guard clean.count > 1 else { return nil }
        
        // Find index of '+' or '-' after index 0
        if let range = clean.range(of: "[+-]", options: .regularExpression, range: clean.index(after: clean.startIndex)..<clean.endIndex) {
            let latStr = String(clean[..<range.lowerBound])
            let lonStr = String(clean[range.lowerBound...])
            
            if let lat = Double(latStr), let lon = Double(lonStr) {
                return (lat, lon)
            }
        }
        return nil
    }

    // Transferable definition for Video URL
    private struct Movie: Transferable {
        let url: URL
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                // Copy to a temp location so we have a persistent URL for the scope of processing
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                try FileManager.default.copyItem(at: received.file, to: tempFile)
                return Movie(url: tempFile)
            }
        }
    }

    nonisolated private func processVideoData(_ url: URL) async -> (CGImage, CLLocation?, Date?)? {
         let asset = AVAsset(url: url)
         
         // Cleanup: If the URL is our temporary usage one, we should ideally delete it after function exit? 
         // But Transferable 'importing' block owns the file creation. Caller should manage?
         // We will assume caller handles cleanup or OS handles temp folder.
            
         var foundLocation: CLLocation?
            
            // Extract Location
            if let metadata = try? await asset.load(.metadata),
               let locationItem = metadata.first(where: { $0.commonKey == .commonKeyLocation }),
               let locString = try? await locationItem.load(.stringValue),
               let (lat, lon) = await Self.parseISO6709(locString) {
                foundLocation = CLLocation(latitude: lat, longitude: lon)
            }
            
            // Extract Creation Date
            var foundDate: Date?
            if let metadata = try? await asset.load(.metadata),
               let dateItem = metadata.first(where: { $0.commonKey == .commonKeyCreationDate }) {
                // Try dateValue first, then stringValue parsing if needed
                if let d = try? await dateItem.load(.dateValue) {
                    foundDate = d
                } else if let s = try? await dateItem.load(.stringValue) {
                     // Basic ISO parser if needed, or leave nil
                     // usually commonKeyCreationDate via load(.dateValue) works for recent iOS
                }
            }
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            
            // Frame Selection
            guard let duration = try? await asset.load(.duration).seconds else { return nil }
            let sampleCount = 15
            var bestFrame: CGImage?
            var bestScore: Float = -1.0
            
            let step = duration / Double(sampleCount)
            for i in 0..<sampleCount {
                 let time = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
                 if let image = try? await generator.image(at: time).image {
                     
                     let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
                     let classifyRequest = VNClassifyImageRequest()
                     
                     let handler = VNImageRequestHandler(cgImage: image, options: [:])
                     try? handler.perform([aestheticsRequest, classifyRequest])
                     
                     // 1. Check for UI/Screenshot content
                     var isUI = false
                     if let classifications = classifyRequest.results {
                         for classification in classifications.prefix(3) {
                             let id = classification.identifier.lowercased()
                             if id.contains("screenshot") || id.contains("web_site") || id.contains("menu") {
                                 isUI = true
                                 break
                             }
                         }
                     }
                     // 2. Aesthetic score
                     // Since I removed the complex logic in previous edit, let's just restore simple best score logic
                     if let aestheticResults = aestheticsRequest.results?.first {
                         let score = aestheticResults.overallScore
                         if score > bestScore {
                             bestScore = score
                             bestFrame = image
                         }
                     } else if bestFrame == nil {
                         bestFrame = image
                     }
                 }
            }
            
            // If no "good" frame found, fallback to first frame
            if let final = bestFrame {
                return (final, foundLocation, foundDate)
            } else if let startFrame = try? await generator.image(at: .zero).image {
                return (startFrame, foundLocation, foundDate)
            }
            
            return nil
    }

    nonisolated private func processVideoData(_ data: Data) async -> (CGImage, CLLocation?, Date?)? {
        // Safe to run off-main-actor
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        do {
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return await processVideoData(tempURL)
        } catch {
             print("❌ processVideoData(Data) failed: \(error)")
             return nil
        }
    }

}

