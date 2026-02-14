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
import CoreLocation
import AVFoundation
import CoreMedia
import SwiftData

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
    @Published public var sessionDepthData: [Data?] = [] // Depth maps parallel to sessionImages
    @Published public var capturedVideoURL: URL? // For video reprocessing
    @Published public var sessionImages: [PlatformImage] = [] // For multi-image capture
    @Published public var activeSessionID: String = UUID().uuidString // Session Persistence
    
    // MARK: - Orientation-Safe Image Setters
    // All image assignments must go through these to guarantee normalized orientation.
    
    /// Sets `capturedImage` with orientation baked into pixels (normalized to .up).
    /// Vision analysis should still use the original image's cgImage + imageOrientation.
    func setCapturedImage(_ image: PlatformImage?) {
        #if canImport(UIKit)
        self.capturedImage = image?.fixedOrientation()
        #else
        self.capturedImage = image
        #endif
    }
    
    /// Appends an image to `sessionImages` with orientation normalized.
    func appendSessionImage(_ image: PlatformImage, depthData: Data? = nil) {
        #if canImport(UIKit)
        self.sessionImages.append(image.fixedOrientation())
        #else
        self.sessionImages.append(image)
        #endif
        self.sessionDepthData.append(depthData)
    }
    public var accumulatedContexts: [String] = [] // For sequential context history
    @Published public var isReviewing: Bool = false
    @Published public var peelAmount: CGFloat = 0
    @Published public var rectifiedDocument: PlatformImage?
    public var rectifiedDocumentText: String? // Non-published state to hold text for saving
    @Published public var showingDocumentView: Bool = false
    @Published public var selectedPurposes: Set<String> = []
    @Published public var selectedResults: Set<IntelligenceResult> = []
    @Published public var sessionTitle: String? // Explicit user-selected title
    @Published public var shouldDismiss: Bool = false
    
    /// Derived: True when first analysis has produced results (no explicit state needed)
    public var hasCompletedFirstAnalysis: Bool { !results.isEmpty }
    
    // Map Selection
    @Published public var placeCandidates: [EnrichmentData] = []
    
    @Published public var selectedPlace: EnrichmentData? {
        didSet {
            if isLocationPinned {
                savePinnedState()
            }
        }
    }
    
    @AppStorage("diver.isLocationPinned") public var isLocationPinned: Bool = false {
        didSet {
            objectWillChange.send()
            savePinnedState()
            if !isLocationPinned {
                // Clear persistence if unpinned
                UserDefaults.standard.removeObject(forKey: "diver.pinnedLocation")
            }
        }
    }
    
    @Published public var showingPlaceSelection: Bool = false
    
    // Helper for persistence
    private func savePinnedState() {
        if isLocationPinned, let place = selectedPlace {
            if let data = try? JSONEncoder().encode(place) {
                UserDefaults.standard.set(data, forKey: "diver.pinnedLocation")
                print("📍 VI ViewModel: Persisted pinned location: \(place.title ?? "Unknown")")
            }
        }
    }
    
    private func restorePinnedState() {
        // isLocationPinned is already restored by AppStorage
        if isLocationPinned,
           let data = UserDefaults.standard.data(forKey: "diver.pinnedLocation"),
           let place = try? JSONDecoder().decode(EnrichmentData.self, from: data) {
            self.selectedPlace = place
            print("📍 VI ViewModel: Restored pinned location: \(place.title ?? "Unknown")")
        }
    }
    
    // Renaming
    @Published public var renamingPlace: EnrichmentData?
    @Published public var newPlaceTitle: String = ""
    
    // Pipeline Visualization State
    public enum PipelineStatus: String, CaseIterable, Equatable {
        case idle = "Ready"
        case capturing = "Capturing..."
        case sifting = "Isolating Subject..."
        case reading = "Reading Text..."
        case enriching = "Finding Location..."
        case reasoning = "Understanding Context..."
        case complete = "Complete"
        case failed = "Failed"
        
        public var displayText: String { rawValue }
    }
    @Published public var pipelineStatus: PipelineStatus = .idle
    
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

    
    // MARK: - Context Restoration
    
    /// Reconstructs the accumulated context from an existing session's history.
    /// This should ONLY be called when explicitily "Adding to Context" (resuming a session).
    public func resumeSessionContext(_ sessionID: String) async {
        guard let context = Services.shared.modelContext else { return }
        
        print("🔄 VI ViewModel: Resuming context for session \(sessionID)")
        
        // 1. Fetch Session Metadata (to restore title/location)
        let sessionDescriptor = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        if let session = try? context.fetch(sessionDescriptor).first {
             await MainActor.run {
                 self.sessionTitle = session.title
                 if let name = session.locationName {
                     // We don't overwrite selectedPlace if it's already set by locateContextOnLoad, 
                     // but we can hint it.
                     print("📍 Resumed Session Location: \(name)")
                 }
             }
        }
        
        // 2. Fetch Processed Items (History)
        // We want the most recent items first? Or chronological? 
        // Accumulated context is usually "Past Captures", so chronological order might make sense to tell a story,
        // but often we just append. Let's fetch chronological.
        let itemDescriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        if let items = try? context.fetch(itemDescriptor) {
            let histories = items.compactMap { item -> String? in
                guard let title = item.title else { return nil }
                // Reconstruct a summary line similar to how it's built in capture
                var access = "Capture: \(title)"
                if let summ = item.summary {
                    access += " - \(summ)"
                }
                if let purpose = item.purposes.first {
                    access += " [\(purpose)]"
                }
                return access
            }
            
            await MainActor.run {
                self.accumulatedContexts = histories
                print("✅ VI ViewModel: Reconstructed \(histories.count) context items.")
            }
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
    /// Stores the EXIF orientation that was active when Vision analyzed the captured image.
    /// Needed because `capturedImage` is normalized to `.up` for display, but Vision
    /// coordinates (e.g. VNRectangleObservation) are in the original orientation's coordinate system.
    public var capturedImageVisionOrientation: CGImagePropertyOrientation = .up
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
        
        // Eagerly request Photo Library access to ensure PHAsset lookups work
        Task {
            _ = await PhotosAssetLoader.shared.requestAuthorization()
        }
        
        // Restore pinned state
        restorePinnedState()
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
        
        // 1. Set Session & Metadata FIRST — CRITICAL: Pin location from the item's
        // existing data so locateContextOnLoad skips fresh GPS lookup.
        // This MUST run before any early returns.
        self.activeSessionID = context.sessionID
        self.sessionTitle = context.sessionTitle  // Preserve user's custom title
        self.currentCapturePlaceID = context.placeID
        
        var reprocessLat: Double?
        var reprocessLon: Double?
        if let loc = context.location {
            let parts = loc.split(separator: ",")
            if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                self.currentCaptureCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                reprocessLat = lat
                reprocessLon = lon
            }
        }
        
        // Build selectedPlace from item context to prevent location override
        if let placeName = context.placeName, let lat = reprocessLat, let lon = reprocessLon {
            let itemPlace = EnrichmentData(
                title: placeName,
                descriptionText: "From original capture",
                categories: ["Reprocess"],
                location: context.location ?? placeName,
                placeContext: PlaceContext(
                    name: placeName,
                    categories: [],
                    placeID: context.placeID,
                    latitude: lat,
                    longitude: lon
                )
            )
            self.selectPlace(itemPlace)
            self.isLocationPinned = true
            print("📍 [Reprocess] Pinned location from item: \(placeName)")
        } else if let lat = reprocessLat, let lon = reprocessLon {
            let coordPlace = EnrichmentData(
                title: context.location ?? "Original Location",
                descriptionText: "From original capture",
                categories: ["Reprocess"],
                location: context.location ?? "\(lat),\(lon)",
                placeContext: PlaceContext(
                    name: "Original Location",
                    categories: [],
                    latitude: lat,
                    longitude: lon
                )
            )
            self.selectPlace(coordPlace)
            self.isLocationPinned = true
            print("📍 [Reprocess] Pinned coordinates from item: \(lat),\(lon)")
        } else {
            // No location data on item — allow fresh lookup
            if !isLocationPinned {
                self.selectedPlace = nil
            }
        }
        
        // 2. Load Media (Image vs Video)
        // Use mediaType from the item's model to determine type.
        // Only fall back to byte-sniffing when mediaType is unknown.
        let isVideo: Bool = {
            if let mediaType = context.mediaType {
                return mediaType == "video"
            }
            return self.isDataVideo(context.imageData)
        }()
        
        if isVideo {
            print("🎥 VI ViewModel: Detected Video Data for session \(context.sessionID)")
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            do {
                try context.imageData.write(to: tempURL)
                self.capturedVideoURL = tempURL
                
                // Generate Thumbnail
                let asset = AVAsset(url: tempURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    #if canImport(UIKit)
                    self.setCapturedImage(PlatformImage(cgImage: cgImage))
                    #elseif canImport(AppKit)
                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    self.setCapturedImage(PlatformImage(cgImage: cgImage, size: size))
                    #endif
                    self.siftedImage = self.capturedImage
                }
            } catch {
                print("❌ VI ViewModel: Failed to prepare video for reprocessing: \(error)")
            }
        } else {
            // Image Path
            #if canImport(UIKit)
            if let image = UIImage(data: context.imageData) {
                self.setCapturedImage(image)
                self.siftedImage = self.capturedImage
            } else {
                 print("❌ VI ViewModel: UIImage(data:) failed for session \(context.sessionID). Size: \(context.imageData.count) bytes. Trying fallbacks...")
                 
                 if let source = CGImageSourceCreateWithData(context.imageData as CFData, nil),
                    let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                     let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                     self.setCapturedImage(image)
                     self.siftedImage = self.capturedImage
                     print("✅ VI ViewModel: Recovered image via CGImageSource.")
                 } else {
                     print("❌ VI ViewModel: All image recovery attempts failed.")
                 }
            }
            #endif
        }
        
        // 3. Enter Review Mode
        self.isReviewing = true
        
        // 4. Trigger Analysis immediately
        if let image = self.capturedImage {
            self.analyzeReprocessImage(image)
        } else {
            print("⚠️ VI ViewModel: No image available for analysis after load.")
            self.pipelineStatus = .failed
            self.isAnalyzing = false
        }
        
        // 5. Clear context so we don't loop
        Services.shared.pendingReprocessContext = nil
    }
    
    private func isDataVideo(_ data: Data) -> Bool {
        let len = data.count
        if len < 4 { return false }
        let header = data.prefix(12).map { String(format: "%02hhx", $0) }.joined()
        // Common MP4/MOV signatures (ftyp, moov, etc at start or offset 4)
        // User provided: 0000001c 66747970 (ftyp) 6d703432 (mp42)
        return header.contains("66747970") || header.contains("6d6f6f76") // ftyp or moov
    }
    
    // MARK: - Location Initialization
    public func locateContextOnLoad(subservientTo sessionID: String? = nil) {
        Task {
            // First Principles: Only restore location if we are explicitly entering an existing context.
            // If starting a new session, we want fresh location data.
            
            guard let context = Services.shared.modelContext else { return }
            
            if let targetSessionID = sessionID {
                // RESTORE: Fetch specific session to ensure continuity
                let descriptor = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == targetSessionID })
                if let session = try? context.fetch(descriptor).first,
                   let lat = session.latitude, let lon = session.longitude {
                    let placeName = session.locationName ?? "Resumed Location"
                    
                    let restoredPlace = EnrichmentData(
                        title: placeName,
                        descriptionText: "Restored from session context",
                        categories: ["Resumed"],
                        location: placeName,
                        placeContext: PlaceContext(name: placeName, categories: [], latitude: lat, longitude: lon)
                    )
                    
                    await MainActor.run {
                        self.selectedPlace = restoredPlace
                        self.currentCapturePlaceID = session.placeID
                        print("📍 VI ViewModel: Restored location for session \(targetSessionID): \(placeName)")
                    }
                }
            } else {
                // 2. New Context Flow (Fallback)
                print("📍 Context: Initializing fresh location lookup (No previous session context found)...")
                
                await MainActor.run {
                    if !isLocationPinned || self.selectedPlace == nil {
                        self.selectedPlace = nil
                        self.currentCapturePlaceID = nil
                    }
                }
                
                // CRITICAL: If location is pinned and we have a selection, DO NOT perform fresh lookup.
                let shouldSkipLookup = await MainActor.run { self.isLocationPinned && self.selectedPlace != nil }
                if shouldSkipLookup {
                    print("📍 Context: Location is pinned (\(selectedPlace?.title ?? "Unknown")). Skipping fresh lookup.")
                    return
                }
                
                guard let locService = Services.shared.locationService else { return }
                
                // A. Get Coordinate
                guard let currentLoc = await locService.getCurrentLocation() else {
                    print("⚠️ Context: Could not determine current device location.")
                    return
                }
                
                await MainActor.run { self.currentCaptureCoordinate = currentLoc.coordinate }
                
                // B. Check Contacts (Home/Work)
                if let contactService = Services.shared.contactService {
                    if let home = try? await contactService.getHomeLocation(), home.distance(from: currentLoc) < 150 {
                        let homePlace = EnrichmentData(
                            title: "Home",
                            descriptionText: "Your Personal Context",
                            categories: ["Personal", "Home"],
                            location: "Home",
                            placeContext: PlaceContext(name: "Home", categories: ["Personal"], latitude: home.coordinate.latitude, longitude: home.coordinate.longitude)
                        )
                        await MainActor.run { self.selectPlace(homePlace); self.isLocationPinned = true }
                        return
                    }
                    
                    if let work = try? await contactService.getWorkLocation(), work.distance(from: currentLoc) < 150 {
                        let workPlace = EnrichmentData(
                            title: "Work",
                            descriptionText: "Your Workplace",
                            categories: ["Personal", "Work"],
                            location: "Work",
                            placeContext: PlaceContext(name: "Work", categories: ["Personal"], latitude: work.coordinate.latitude, longitude: work.coordinate.longitude)
                        )
                        await MainActor.run { self.selectPlace(workPlace); self.isLocationPinned = true }
                        return
                    }
                }
                
                // C. MapKit Reverse Geocode
                let geocoder = CLGeocoder()
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(currentLoc)
                    if let best = placemarks.first {
                        let name = best.name ?? best.thoroughfare ?? "Unknown Location"
                        let address = [best.thoroughfare, best.locality].compactMap { $0 }.joined(separator: ", ")
                        
                        print("📍 Context: MapKit found '\(name)'")
                        
                        var finalPlace = EnrichmentData(
                            title: name,
                            image: nil,
                            categories: ["Location"],
                            location: address,
                            placeContext: PlaceContext(name: name, categories: [], placeID: "mk-\(name)", address: address, latitude: currentLoc.coordinate.latitude, longitude: currentLoc.coordinate.longitude)
                        )
                        
                        // D. Enrich with Foursquare
                        if let fsq = Services.shared.foursquareService {
                            if let enriched = try? await fsq.enrich(query: name, location: currentLoc.coordinate) {
                                print("📍 Foursquare enriched MapKit place.")
                                finalPlace = enriched
                            }
                        }
                        
                        await MainActor.run {
                            if self.selectedPlace == nil {
                                self.selectPlace(finalPlace)
                            }
                        }
                    }
                } catch {
                    print("⚠️ Context: Reverse geocoding failed: \(error)")
                }
            }
        }
    }
    
    // Helper to fetch session location and hydrate context
    private func fetchSessionLocation(_ id: String) async -> EnrichmentData? {
        guard let modelContext = Services.shared.modelContext else {
            print("❌ ViewModel: Missing ModelContext in Services")
            return nil
        }
        
        let sessionID = id
        let descriptor = FetchDescriptor<DiverSession>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        
        do {
            let results = try modelContext.fetch(descriptor)
            guard let session = results.first else {
                print("❌ ViewModel: Session \(sessionID) not found in DB. Count: \(results.count)")
                return nil 
            }
            
            // Hydrate Context History
            // Fetch items for this session to rebuild accumulated context
            let itemDescriptor = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            if let items = try? modelContext.fetch(itemDescriptor) {
                let histories = items.compactMap { item -> String? in
                    guard let title = item.title else { return nil }
                    return "Capture: \(title)"
                }
                await MainActor.run {
                    self.accumulatedContexts = histories
                }
            }
            
            // Hydrate Location
            if let lat = session.latitude, let lon = session.longitude {
                let name = session.locationName ?? session.title ?? "Session Location"
                let placeID = session.placeID ?? "session-\(id)"
                
                // Construct PlaceContext
                let placeContext = PlaceContext(
                    name: name,
                    categories: [],
                    placeID: placeID,
                    address: nil, // Could fetch if we had it
                    latitude: lat,
                    longitude: lon
                )
                
                return EnrichmentData(
                    title: name,
                    descriptionText: "Resumed Session Location",
                    categories: ["Location"],
                    location: name,
                    placeContext: placeContext
                )
            }
        } catch {
            print("⚠️ ViewModel: Failed to fetch session: \(error)")
        }
        
        return nil 
    }

    public func analyzeReprocessImage(_ image: PlatformImage) {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        #endif
        
        self.isAnalyzing = true
        self.pipelineStatus = .sifting
        
        Task(priority: .utility) {
            do {
                // Saved payloads are normalized to .up
                let newResults = try await self.processor.process(image: cgImage, orientation: .up, mode: .fullAnalysis)
                
                await MainActor.run {
                    self.results = newResults
                    // self.capturedImage is already set
                    
                    self.pipelineStatus = .reading
                    
                    // Sifted logic
                    if let sifted = newResults.first(where: { if case .siftedSubject = $0 { return true }; return false }),
                       case .siftedSubject(let observation, _) = sifted {
                        Task {
                            // Use captured image's orientation for proper sifted subject rotation
                            let cgOrientation = await MainActor.run { () -> CGImagePropertyOrientation in
                                #if canImport(UIKit)
                                return self.capturedImage?.imageOrientation.cgImagePropertyOrientation ?? .up
                                #else
                                return .up
                                #endif
                            }
                            if let (sImage, sBounds) = await self.extractSiftedImage(
                                observation: UnsafeSendable(value: observation),
                                frame: UnsafeSendable(value: cgImage),
                                orientation: cgOrientation
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
                    // Note: Context analysis Task (below) will set .reasoning → .complete
                }
                
                // NEW: Automatically trigger "Analyze Context" after reprocessing
                // Wait for verification loop to finish kicking off results, then trigger context
                Task {
                     // Add a small delay to allow UI to settle?
                     try? await Task.sleep(nanoseconds: 500_000_000)
                     await MainActor.run {
                        print("🤖 Reprocessing: Auto-triggering Context Analysis...")
                        Task {
                             await MainActor.run { self.pipelineStatus = .reasoning }
                             await self.regenerateContextSuggestions(for: self.selectedPlace)
                             await MainActor.run { self.pipelineStatus = .complete }
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

            cameraManager.onPhotoCaptured = { [weak self] imageData, depthData in
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
                    self.setCapturedImage(image)
                    
                    await MainActor.run {
                        self.pipelineStatus = .sifting
                    }
                    if let img = self.capturedImage {
                        self.appendSessionImage(img, depthData: depthData)
                        // Save to Photo Library as Backup
                        self.saveImageToPhotoLibrary(img)
                    }
                    
                    #if canImport(UIKit)
                    let cgImage = image?.cgImage
                    // Use the actual image orientation, not the device's current orientation
                    let visionOrientation = image?.imageOrientation.cgImagePropertyOrientation ?? self.currentOrientation
                    self.capturedImageVisionOrientation = visionOrientation
                    #elseif canImport(AppKit)
                    let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    let visionOrientation: CGImagePropertyOrientation = .up // NSImage typically normalizes or we assume up
                    #else
                    let cgImage: CGImage? = nil
                    let visionOrientation: CGImagePropertyOrientation = .up
                    #endif
                    
                    if let cgImage = cgImage {
                         // Capture Mode: Full Analysis (mode: .fullAnalysis)
                         // We run Barcode + Text + Classification AND Check for Sifted ROI
                         
                    do {
                        #if canImport(UIKit)
                        print("📸 Vision Orientation: \(visionOrientation.rawValue) (Raw: \(image?.imageOrientation.rawValue ?? -1))")
                        #else
                        print("📸 Vision Orientation: \(visionOrientation.rawValue)")
                        #endif
                        
                        let fullResults = try await self.processor.process(image: cgImage, orientation: visionOrientation, mode: .fullAnalysis)
                        print("✅ Raw Analysis Results: \(fullResults.map { $0.title })")
                        
                        // Override the results with the HIGH FIDELITY capture results
                        var resultsWithPurpose = fullResults
                        
                        // NEW: Concurrent Enrichment Pipeline
                        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                            print("🚀 Enrichment Pipeline: Starting Concurrent Enrichment...")
                            
                            await MainActor.run { self.pipelineStatus = .enriching }
                            
                            // Capture history on MainActor before awaiting
                            let currentHistory = self.accumulatedContexts
                            
                            // 1. Determine Location Truthing Strategy (Early)
                            // Priority: Imported Metadata > Live GPS
                            var currentLocation: CLLocation? = self.capturedMediaLocation
                            
                            if currentLocation == nil, let locService = Services.shared.locationService {
                                 // Only fetch live location if we don't have explicit media metadata
                                 currentLocation = await locService.getCurrentLocation()
                            }
                            
                            // Update State immediately so UI reflects the "truth"
                            // CRITICAL: Do NOT overwrite if user has already selected a place
                            let hasUserSelection = await MainActor.run { self.selectedPlace != nil }
                            if let loc = currentLocation, !hasUserSelection {
                                 await MainActor.run {
                                     self.currentCaptureCoordinate = loc.coordinate
                                 }
                            }
                            
                            // 2. Call Enrichment with Authoritative Location
                            let (enriched, stepSummary, candidates) = await self.enrichContext(
                                from: fullResults, 
                                accumulatedContext: currentHistory,
                                locationOverride: currentLocation
                            )
                            
                            // Home/Work Enrichment
                            var finalCandidates = candidates
                            if let contactService = Services.shared.contactService {
                                let home = try? await contactService.getHomeLocation()
                                let work = try? await contactService.getWorkLocation()

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
                                
                                // FIX: Dialog Hang (First Principles)
                                // We MUST transition out of .enriching here.
                                // If we found a place, great. If not, we still stop "Locating..."
                                print("📍 Enrichment Complete. Selected: \(self.selectedPlace?.title ?? "None"). Status -> Reasoning")
                                self.pipelineStatus = .reasoning
                                
                                // Update MainActor state with new summary
                                if let summary = stepSummary {
                                    self.accumulatedContexts.append("Capture \(self.accumulatedContexts.count + 1): " + summary)
                                }
                            }
                                
                            // Verify State Consistency: Ensure we didn't regress to .enriching due to a race
                            // (No-op here, rely on MainActor serialization)
                                // We replace .qr/.text with .richWeb if found
                                var finalResults: [IntelligenceResult] = []
                                
                                // Check if enrichment produced a rich web result
                                let _ = enriched.contains { if case .richWeb = $0 { return true }; return false }
                                
                                // First, add all non-obsolete results
                                for result in resultsWithPurpose {
                                    // FIX: Do not suppress QR/Text even if Rich Web is present.
                                    // User wants to see the raw QR code as a fallback/confirmation.
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
                        
                        // Update UI state (hasCompletedFirstAnalysis is now derived from !results.isEmpty)
                        await MainActor.run {
                            self.pipelineStatus = .complete
                        }
                        
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
            print("📸 Starting Import Task...")
            
            // Define cleanup in case of failure
            // We use a local var to track success to avoid premature reset
            var loadingSuccess = false
            
            defer {
                if !loadingSuccess {
                   Task { @MainActor in
                       print("❌ Import Task Failed or Cancelled - Resetting UI")
                       self.isReviewing = false
                       self.showingSaveError = true
                       self.saveErrorMessage = "Failed to load selected item. Please try again."
                   }
                }
            }

            do {
                var finalCGImage: CGImage?
                var finalImage: PlatformImage?
                
                // 1. Try Video first (Safe URL loading)
                // We use a specific do-catch for transferable loading to diagnose issues
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
                     print("📸 Attempting Data Load...")
                     guard let data = try await item.loadTransferable(type: Data.self) else {
                         print("❌ Failed to load Data transferable")
                         return // Defer triggers failure handling
                     }
                     print("✅ Loaded \(data.count) bytes")
                     
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
                
                guard let cgImage = finalCGImage else {
                    print("❌ Could not create CGImage from loaded content")
                    return
                }
                let image = finalImage 
                
                loadingSuccess = true // Mark success to prevent defer failure handling
                
                await MainActor.run { 
                    self.isAnalyzing = true 
                    self.pipelineStatus = .sifting
                }
                    
                    // Analyze for interactive results
                    // Use the actual image orientation — identical to the camera capture path (line 856).
                    // .cgImage returns raw (unrotated) pixels; Vision needs the orientation hint
                    // to produce coordinates in the correctly-oriented space.
                    #if canImport(UIKit)
                    let visionOrientation = (image as? UIImage)?.imageOrientation.cgImagePropertyOrientation ?? .up
                    self.capturedImageVisionOrientation = visionOrientation
                    #else
                    let visionOrientation: CGImagePropertyOrientation = .up
                    #endif
                    print("🧠 Starting Intelligence Processing in .fullAnalysis mode (orientation=\(visionOrientation.rawValue))...")
                    let newResults = try await self.processor.process(image: cgImage, orientation: visionOrientation, mode: .fullAnalysis)
                    
                    await MainActor.run {
                        print("🖼 Photo Picker: Analysis complete, transitioning to Reviewing state")
                        self.results = newResults
                        self.setCapturedImage(image)
                        
                        // Extract sifted image if found
                        if let sifted = newResults.first(where: { if case .siftedSubject = $0 { return true }; return false }),
                           case .siftedSubject(let observation, _) = sifted {
                            Task {
                            // Use captured image's orientation for proper sifted subject rotation
                                let cgOrientation = await MainActor.run { () -> CGImagePropertyOrientation in 
                                    #if canImport(UIKit)
                                    return self.capturedImage?.imageOrientation.cgImagePropertyOrientation ?? .up
                                    #else
                                    return .up
                                    #endif
                                }
                                if let (sImage, sBounds) = await self.extractSiftedImage(
                                    observation: UnsafeSendable(value: observation),
                                    frame: UnsafeSendable(value: cgImage), // Overload used for CGImage
                                    orientation: cgOrientation
                                ) {
                                    await MainActor.run {
                                        self.siftedImage = sImage
                                        self.siftedBoundingBox = sBounds
                                        self.pipelineStatus = .reading // Complete sifting
                                    }
                                }
                            }
                        } else {
                            // No sifted subject - update status immediately
                            self.pipelineStatus = .reading
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
                        // Verification complete - mark pipeline as complete
                        await MainActor.run {
                            self.pipelineStatus = .complete
                            self.isAnalyzing = false
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
    
    // MARK: - Batch Photo Import (from Sidebar)
    
    /// Loads all selected photos into sessionImages as a single capture session,
    /// runs Vision analysis on each, merges results, and enters review mode.
    public func processImportedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        print("📥 Processing \(items.count) imported photos as single session...")
        
        // Reset state for new import session
        self.activeSessionID = UUID().uuidString
        self.sessionImages = []
        self.sessionDepthData = []
        self.results = []
        self.accumulatedContexts = []
        self.siftedBoundingBox = nil
        self.capturedImage = nil
        self.isReviewing = true // Show loading state immediately
        self.isAnalyzing = true
        self.pipelineStatus = .sifting
        
        Task {
            var allResults: [IntelligenceResult] = []
            var loadedCount = 0
            
            for (index, item) in items.enumerated() {
                print("📸 Loading import \(index + 1)/\(items.count)...")
                
                do {
                    var finalCGImage: CGImage?
                    var finalImage: PlatformImage?
                    
                    // 1. Try Video first
                    if let movie = try? await item.loadTransferable(type: Movie.self) {
                        if let (cgImage, location, date) = await processVideoData(movie.url) {
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
                    
                    // 2. Fallback to Data (Images)
                    if finalCGImage == nil {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            print("⚠️ Skipping import \(index + 1) - failed to load data")
                            continue
                        }
                        
                        #if canImport(UIKit)
                        if let image = UIImage(data: data) {
                            finalImage = image
                            finalCGImage = image.cgImage
                            
                            // Extract date from EXIF
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
                                            // Only set date from first image (session date)
                                            if self.capturedMediaDate == nil {
                                                self.capturedMediaDate = date
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        #endif
                    }
                    
                    guard let cgImage = finalCGImage, let image = finalImage else {
                        print("⚠️ Skipping import \(index + 1) - could not create image")
                        continue
                    }
                    
                    loadedCount += 1
                    
                    await MainActor.run {
                        // Apply fixedOrientation before adding to session to bake in EXIF rotation
                        
                        self.appendSessionImage(image)
                        
                        // Set first image as the primary captured image
                        if self.capturedImage == nil {
                            self.setCapturedImage(image)
                        }
                    }
                    
                    // Run Vision analysis on this image
                    #if canImport(UIKit)
                    let visionOrientation = (image as? UIImage)?.imageOrientation.cgImagePropertyOrientation ?? .up
                    self.capturedImageVisionOrientation = visionOrientation
                    #else
                    let visionOrientation: CGImagePropertyOrientation = .up
                    #endif
                    
                    print("🧠 Analyzing import \(index + 1)/\(items.count) (orientation=\(visionOrientation.rawValue))...")
                    let imageResults = try await self.processor.process(image: cgImage, orientation: visionOrientation, mode: .fullAnalysis)
                    allResults.append(contentsOf: imageResults)
                    
                } catch {
                    print("⚠️ Failed to process import \(index + 1): \(error)")
                }
            }
            
            // Merge all results and enter review mode
            await MainActor.run {
                print("📥 Import complete: \(loadedCount)/\(items.count) loaded, \(allResults.count) results")
                self.results = allResults
                self.pipelineStatus = .complete
                self.isAnalyzing = false
                self.isReviewing = true
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
                    // Use captured image's orientation for proper sifted subject rotation
                     let cgOrientation = await MainActor.run { () -> CGImagePropertyOrientation in
                         #if canImport(UIKit)
                         return self.capturedImage?.imageOrientation.cgImagePropertyOrientation ?? .up
                         #else
                         return .up
                         #endif
                     }
                    if let (sImage, sBounds) = await self.extractSiftedImage(
                        observation: UnsafeSendable(value: result),
                        frame: UnsafeSendable(value: cgImage),
                        orientation: cgOrientation
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
            // generateMaskedImage() returns pixels in the raw sensor coordinate space
            // (e.g. landscape for rear camera in portrait mode). We must apply the
            // camera orientation to rotate the mask upright, matching the main image.
            let uiOrientation = uiImageOrientation(from: orientation)
            let orientedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)
            // Bake the orientation into actual pixels
            let uiImage = orientedImage.normalizedOrientation()
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
    nonisolated private func uiImageOrientation(from orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
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
        let allDepthData = self.sessionDepthData // Parallel to sessionImages
        let primaryDepth = allDepthData.first ?? nil // Depth for the primary/master image
        
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
        
        // Find most prominent text from results as fallback
        let prominentText: String? = {
            // Priority 1: Document OCR text (first meaningful line)
            for result in self.results {
                if case .document(_, let text, _, _) = result, let text = text {
                    let firstLine = text.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let line = firstLine, !line.isEmpty, line.count > 3 {
                        return String(line)
                    }
                }
            }
            
            // Priority 2: Semantic labels (first capitalized)
            for result in self.results {
                if case .semantic(let label, _) = result {
                    return label.capitalized
                }
            }
            
            // Priority 3: Any result title
            return self.results.first?.title
        }()
        
        // Use the selected intent as the primary title if it exists, otherwise fall back to enriched title
        let calculatedTitle = self.sessionTitle ?? validIntent ?? prominentText ?? "Visual Capture"
        
        // Ensure the calculated title is actually used or stored
        if self.sessionTitle == nil {
            self.sessionTitle = calculatedTitle
        }
        
        Task.detached(priority: .utility) { () -> Void in
            #if canImport(UIKit)
            // Fix orientation (bake it in) before saving to data, as jpegData strips EXIF orientation tags
            let normalizedImage = imageToSave?.fixedOrientation()
            let capturedData = normalizedImage?.jpegData(compressionQuality: 0.8)
            
            // Normalize sifted image orientation before saving (apply rotation to pixel data)
            let normalizedSifted = siftedImg?.normalizedOrientation()
            let siftedData = normalizedSifted?.pngData()
            
            // Also normalize attachment images
            let attachmentData = sessionImgs.compactMap { $0.fixedOrientation().jpegData(compressionQuality: 0.8) }
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
            
            // 2. Auto-save detected documents (rectified)
            #if canImport(UIKit)
            if let capturedImage = imageToSave {
                // Find document results to auto-rectify and save
                let documentResults = currentResults.compactMap { result -> (VNRectangleObservation, String?, String?)? in
                    if case .document(let obs, let text, let label, _) = result {
                        return (obs, text, label)
                    }
                    return nil
                }
                
                for (observation, text, label) in documentResults {
                    if let cgImage = capturedImage.cgImage {
                        // Rectify the document
                        #if canImport(UIKit)
                        let orientation = capturedImage.imageOrientation.cgImagePropertyOrientation
                        #else
                        let orientation: CGImagePropertyOrientation = .up
                        #endif
                        
                        if let rectifiedCGImage = await self.performRectification(
                            observation: UnsafeSendable(value: observation),
                            image: UnsafeSendable(value: cgImage),
                            orientation: orientation
                        ) {
                            // CIPerspectiveCorrection outputs an upright image, so we must specify .up to avoid re-rotation
                            let rectifiedImage = UIImage(cgImage: rectifiedCGImage, scale: 1.0, orientation: .up)
                            if let rectifiedData = rectifiedImage.jpegData(compressionQuality: 0.9) {
                                // Create queue item for the rectified document
                                let documentTitle = "Doc: " + (label ?? text?.prefix(50).description ?? "Scanned")
                                let docQueueItem = DiverQueueItem.from(
                                    documentImage: rectifiedData,
                                    title: documentTitle,
                                    tags: [],
                                    text: text,
                                    purposes: purposes,
                                    date: Date(),
                                    sessionID: sessionID,
                                    placeID: capturePlaceID,
                                    latitude: captureCoordinate?.latitude,
                                    longitude: captureCoordinate?.longitude,
                                    locationName: selectedPlaceTitle,
                                    attachments: []
                                )
                                try queueStore.enqueue(docQueueItem)
                                print("📄 Auto-saved rectified document: \(documentTitle)")
                            }
                        }
                    }
                }
            }
            #endif
            
            // 3. Create Intelligent Queue Items (Master + Children)
            do {
                let queueItems = DiverQueueItem.items(intelligenceResults: currentResults, capturedImage: capturedData, siftedImage: siftedData, attachments: attachmentData, purposes: purposes, sessionID: sessionID, contextImageURL: contextImageURL, placeID: capturePlaceID, latitude: captureCoordinate?.latitude, longitude: captureCoordinate?.longitude, locationName: selectedPlaceTitle, depthPayload: primaryDepth, attachmentDepthPayloads: allDepthData)
                
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
                        
                        // Don't reset VM - it should persist across navigation
                        // Reset will happen when user dismisses the entire capture session
                        self.shouldDismiss = true
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
    
    public func handleDocumentSelection(_ observation: VNRectangleObservation, text: String? = nil, rectifiedImageData: Data? = nil) {
        self.rectifiedDocumentText = text
        
        // Prefer the pre-rectified image from IntelligenceProcessor if available
        if let data = rectifiedImageData, let image = UIImage(data: data) {
            print("📐 handleDocumentSelection: Using pre-rectified image \(image.size), orientation=\(image.imageOrientation.rawValue)")
            // Normalize orientation — the JPEG from DocumentManager may carry EXIF rotation
            self.rectifiedDocument = image.fixedOrientation()
            self.showingDocumentView = true
            return
        }
        print("📐 handleDocumentSelection: No pre-rectified data, using fallback rectification")
        
        // Fallback: rectify from captured image (for cases without pre-rectified data)
        Task {
            guard let capturedImage = await MainActor.run(body: { self.capturedImage }) else { return }
            #if canImport(UIKit)
            guard let cgImage = capturedImage.cgImage else { return }
            // capturedImage is already normalized to .up (pixels are upright),
            // so pass .up — no additional rotation needed by DocumentManager.
            // Vision rectangle coordinates are in display-space which matches
            // the normalized pixel layout.
            let orientation: CGImagePropertyOrientation = .up
            #elseif canImport(AppKit)
            guard let cgImage = capturedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let orientation: CGImagePropertyOrientation = .up
            #endif
            
            if let cgImage = await performRectification(
                observation: UnsafeSendable(value: observation),
                image: UnsafeSendable(value: cgImage),
                orientation: orientation
            ) {
                await MainActor.run {
                    #if canImport(UIKit)
                    self.rectifiedDocument = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
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
        image: UnsafeSendable<CGImage>,
        orientation: CGImagePropertyOrientation
    ) async -> CGImage? {
        // Delegate to DocumentManager which uses CGContext-based rotation (proven reliable)
        let docManager = DocumentManager()
        guard let jpegData = docManager.rectifyImage(
            image.value,
            using: observation.value,
            orientation: orientation
        ) else { return nil }
        
        // Extract the CGImage from the JPEG
        #if canImport(UIKit)
        return UIImage(data: jpegData)?.cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: jpegData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return cgImage
        #else
        return nil
        #endif
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
    
    public func regenerateContextSuggestions(for place: EnrichmentData?) async {
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
        accumulatedContexts = []
        
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
        
        // Conditional Reset for Pinned Location
        if !isLocationPinned {
            selectedPlace = nil
        }
        
        showingPlaceSelection = false
        rectifiedDocument = nil
        rectifiedDocumentText = nil
        capturedImageVisionOrientation = .up
        showingDocumentView = false
        
        // Reset internal state
        isAnalyzing = false
        isReviewing = false
        // hasCompletedFirstAnalysis is now derived from !results.isEmpty (auto-reset)
        pipelineStatus = .idle
        shouldDismiss = false
        
        print("🔄 Visual Intelligence VM: State Reset")
        // debugPrint(Thread.callStackSymbols) // Uncomment to trace caller causing loop
    }
    
    public func reCapture() {
        // Soft reset for taking another photo in the SAME session
        self.results = []
        self.capturedImage = nil
        self.siftedImage = nil 
        self.siftedBoundingBox = nil
        self.activeObservation = nil
        self.isReviewing = false
        self.pipelineStatus = .idle
        
        // Do NOT reset session ID, pinned location, or place
    }
    
    // MARK: - UI Helpers
    
    
    /// Transforms a Vision bounding box to account for device orientation
    public func transformBoundingBoxForOrientation(_ box: CGRect, orientation: CGImagePropertyOrientation) -> CGRect {
        switch orientation {
        case .up, .upMirrored:
            // No rotation needed
            return box
            
        case .down, .downMirrored:
            // 180° rotation: flip both X and Y
            return CGRect(
                x: 1.0 - box.maxX,
                y: 1.0 - box.maxY,
                width: box.width,
                height: box.height
            )
            
        case .left, .leftMirrored:
            // 90° counter-clockwise: swap dimensions, transform coordinates
            return CGRect(
                x: box.minY,
                y: 1.0 - box.maxX,
                width: box.height,
                height: box.width
            )
            
        case .right, .rightMirrored:
            // 90° clockwise: swap dimensions, transform coordinates
            return CGRect(
                x: 1.0 - box.maxY,
                y: box.minX,
                width: box.height,
                height: box.width
            )
        }
    }
    
    public func convertBoundingBox(_ box: CGRect, to viewSize: CGSize, imageAspectRatio: CGFloat = 0.75) -> CGRect {
        // Vision: Origin Bottom-Left, Normalized
        // SwiftUI: Origin Top-Left, Points
        // Content Mode: .aspectFill (Crops to fill)
        
        // 1. Calculate the Aspect Fill Rect (The Frame of the "Image" inside the View)
        // Ratio = W / H
        // View Ratio
        let _ = viewSize.width / viewSize.height
        
        // If View is "Wider" than Image (relative to ratios) -> Image fits Width, Crops Vertically?
        // No. If View (1.0) > Image (0.5), View is fat, Image is skinny.
        // To fill View Width, we scale Image. Height becomes huge. Top/Bot cropped.
        
        // Let's use scale factor overlap
        // Target: View. Source: Image (Aspect only)
        // Scale to FILL
        let _ = viewSize.width / imageAspectRatio // Width based (if Height was 1)
        // Wait, simpler:
        // Image Size (Virtual) = (imageAspectRatio * 1000, 1000)
        let virtualW = imageAspectRatio * 1000
        let virtualH = 1000.0
        
        let scaleX = viewSize.width / virtualW
        let scaleY = viewSize.height / virtualH
        let scale = max(scaleX, scaleY)
        
        let fillW = virtualW * scale
        let fillH = virtualH * scale
        
        // 2. Offsets (Center)
        let offsetX = (viewSize.width - fillW) / 2.0
        let offsetY = (viewSize.height - fillH) / 2.0
        
        // 3. Project Normalized Box
        // Box.minX * fillW + offsetX
        let x = offsetX + (box.minX * fillW)
        
        // Flip Y: Vision (0 is Bottom) -> View (0 is Top)
        // Normalized Y=0 (Bottom) maps to fillH (Bottom relative to image rect)
        // Normalized Y=1 (Top) maps to 0 (Top relative to image rect)
        // rect.y = 1 - maxY
        let y = offsetY + ((1.0 - box.maxY) * fillH)
        
        let w = box.width * fillW
        let h = box.height * fillH
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    // MARK: - Enrichment Pipeline
    
    private enum EnrichmentSource {
        case web(URL, EnrichmentData)
        case places([EnrichmentData])
    }
    
    private let contextService = ContextQuestionService()

    private func enrichContext(from initialResults: [IntelligenceResult], accumulatedContext: [String], locationOverride: CLLocation? = nil) async -> ([IntelligenceResult], String?, [EnrichmentData]) {
        if Task.isCancelled { return ([], nil, []) }
        
        // Services
        let webService = self.webViewService
        let locService = Services.shared.locationService
//        let fsService = Services.shared.foursquareService
        
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
            // Optimization: If location is pinned or already selected, skip searching nearby Foursquare venues.
            let existingSelection = await MainActor.run { self.selectedPlace }
            let pinned = await MainActor.run { self.isLocationPinned }
            
            if (pinned || existingSelection != nil), let selection = existingSelection {
                print("📍 Enrichment: Using existing selection/pin for '\(selection.title ?? "Unknown")'. Skipping nearby search.")
                return .places([selection])
            }

            // Use override if available (e.g. from Metadata), otherwise fetch live
            let searchLocation: CLLocation?
            if let override = locationOverride {
                searchLocation = override
            } else {
                searchLocation = await locService?.getCurrentLocation()
            }
            
//            guard let location = searchLocation else { return nil }
            
            // Refinement: If we have a product or web title, we could technically search for stores matching it?
//            // For now, generic nearby search is safest.
//            guard let fsService = fsService else { return nil }
//            if let candidates = try? await fsService.searchNearby(location: location.coordinate, limit: 50), !candidates.isEmpty {
//                return .places(candidates)
//            }
            if let existing = existingSelection {
                return .places([existing])
            }
            return .places([])
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
         let asset = AVURLAsset(url: url)
         
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
                } else if let _ = try? await dateItem.load(.stringValue) {
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
                     if let classifications = classifyRequest.results {
                         for classification in classifications.prefix(3) {
                             let id = classification.identifier.lowercased()
                             if id.contains("screenshot") || id.contains("web_site") || id.contains("menu") {
                                 // isUI = true // Placeholder for future use
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

// MARK: - Extensions

#if canImport(UIKit)
extension UIImage.Orientation {
    public var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        case .left: return .left
        @unknown default: return .up
        }
    }
}

extension UIImage {
    /// Returns a new UIImage with orientation .up by rendering the image in the correct orientation
    func normalizedOrientation() -> UIImage {
        // If already .up, return self
        guard imageOrientation != .up else { return self }
        
        // Render the image in correct orientation
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalized ?? self
    }
}
#endif

