import Foundation
import AVFoundation
import Vision
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

import CoreML
import VideoToolbox

/// Handles live camera feed and schedules Vision requests over incoming frames.
/// Agent [CORE] - Responsible for Camera Session and Intent Launch Foundation
@MainActor
public final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published public var isReady = false
    @Published public var session = AVCaptureSession()
    @Published public var isRecording = false
    @Published public private(set) var extractedBarcodeURLs: [URL] = []
    
    // SAM 2.1 Native Alpha Mask (Pixel-perfect overlay)
    @Published public private(set) var currentSegmentationMask: CGImage?
    @Published public private(set) var previewFrame: CGImage?
    @Published public private(set) var detectedDocuments: [VNRectangleObservation] = []
    
    private let sessionQueue = DispatchQueue(label: "com.diver.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    // Dependencies
    private let barcodeScanner: VNDetectBarcodesRequest
    private let documentScanner: VNDetectDocumentSegmentationRequest
    nonisolated private let samSegmentationService: (any SAM2Segmenting)?
    
    // Thread-safe state for the background capture queue
    private final class BackgroundState: @unchecked Sendable {
        var lastAnalysisTime: CFTimeInterval = 0
        var frameCount: Int = 0
        let lock = NSLock()
    }
    
    private let bgState = BackgroundState()
    private let analysisInterval: CFTimeInterval = 1.0 / 10.0 // 10 fps
    
    public var onFrameCaptured: (@MainActor @Sendable (CVPixelBuffer) -> Void)?
    /// Callback delivers (imageData, depthData?) atomically so depth is always paired with the correct photo
    public var onPhotoCaptured: (@MainActor @Sendable (Data, Data?) -> Void)?
    
    public override init() {
        // Default initializer for testing or when dependencies are not needed immediately
        // In a real app, you might want to inject these.
        self.barcodeScanner = VNDetectBarcodesRequest()
        self.documentScanner = VNDetectDocumentSegmentationRequest()
        
        #if os(iOS)
        // SAM 2.1 is available on iOS native client
        self.samSegmentationService = SAM2SegmentationService()
        #else
        self.samSegmentationService = nil
        #endif
        
        super.init()
        if !isTesting {
            checkPermissions()
        }
    }
    
    // Designated initializer for dependency injection
    public init(barcodeScanner: VNDetectBarcodesRequest = VNDetectBarcodesRequest()) {
        self.barcodeScanner = barcodeScanner
        self.documentScanner = VNDetectDocumentSegmentationRequest()
        
        #if os(iOS)
        // SAM 2.1 is available on iOS native client
        self.samSegmentationService = SAM2SegmentationService()
        #else
        self.samSegmentationService = nil
        #endif
        
        super.init()
        if !isTesting {
            checkPermissions()
        }
    }
    
    private var isTesting: Bool {
        return NSClassFromString("XCTest") != nil
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.startSession() }
            }
        default:
            break
        }
    }
    
    public func startSession() {
        if !session.isRunning {
             // If not configured, configure first
             if session.inputs.isEmpty {
                 configureSession()
             }
             
             // Swift 6: AVCaptureSession is non-Sendable in strict mode. 
             // Since session is @Published (MainActor), startRunning() must be called
             // either on MainActor or via a dedicated actor. We will call it directly.
             self.session.startRunning()
             self.isReady = true
        }
    }
    
    public func stopSession() {
        if session.isRunning {
             self.session.stopRunning()
             self.isReady = false
        }
    }
    
    private func configureSession() {
        // Run configuration synchronously on MainActor where `session` naturally lives, 
        // to avoid Sendable reference warnings.
        self.session.beginConfiguration()
            
            // Prefer depth-capable device (dual/triple/LiDAR), fall back to wide-angle
            let videoDevice: AVCaptureDevice? = {
                #if os(iOS)
                if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                    return triple
                }
                if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                    return dualWide
                }
                if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                    return dual
                }
                #endif
                return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }()
            
            guard let videoDevice = videoDevice,
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                self.session.commitConfiguration()
                return
            }
            
            if self.session.canAddInput(videoInput) {
                self.session.addInput(videoInput)
            }
            
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
            }
            
            #if os(iOS)
            // Select a device format that supports depth data.
            // Use .inputPriority so we can set the format directly instead of relying on presets.
            self.session.sessionPreset = .inputPriority
            
            // Find the best format: prefer highest-resolution photo format with depth support
            let depthFormats = videoDevice.formats.filter { format in
                !format.supportedDepthDataFormats.isEmpty
            }
            
            if let bestFormat = depthFormats.last { // .last = highest resolution
                do {
                    try videoDevice.lockForConfiguration()
                    videoDevice.activeFormat = bestFormat
                    
                    // Also set the depth format to the highest-resolution depth format
                    if let bestDepthFormat = bestFormat.supportedDepthDataFormats.last {
                        videoDevice.activeDepthDataFormat = bestDepthFormat
                    }
                    
                    videoDevice.unlockForConfiguration()
                    print("📐 Selected depth-capable format: \(bestFormat.formatDescription)")
                } catch {
                    print("📐 Failed to lock device for depth format: \(error)")
                }
            }
            
            // Enable depth data delivery if supported (should be true now with depth format)
            if self.photoOutput.isDepthDataDeliverySupported {
                self.photoOutput.isDepthDataDeliveryEnabled = true
                print("📐 Depth data delivery enabled")
            } else {
                print("📐 Depth data delivery not supported (no depth-capable format found)")
            }
            #endif
            
            self.session.commitConfiguration()
    }
    
    
    public func capturePhoto() {
        if isTesting {
            print("📸 CameraManager: Test mode, simulating capture...")
            // Create a fake image data for tests
            #if canImport(UIKit)
            let image = UIImage(systemName: "photo") ?? UIImage()
            let data = image.jpegData(compressionQuality: 0.8)
            #elseif canImport(AppKit)
            let image = NSImage(size: NSSize(width: 100, height: 100))
            if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                image.addRepresentation(rep)
            }
            let data = image.tiffRepresentation
            #else
            let data: Data? = nil
            #endif
            
            if let data = data {
                onPhotoCaptured?(data, nil)
            }
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = CMVideoDimensions(width: 4032, height: 3024) // Replaces `isHighResolutionPhotoEnabled` (iOS 16+)
        
        // Request depth data if available
        #if os(iOS)
        if photoOutput.isDepthDataDeliverySupported {
            settings.isDepthDataDeliveryEnabled = true
        }
        #endif
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 1. Maintain preview frame
        var cgImageOut: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageOut)
        let cgImageOutVar = cgImageOut
        if let cgImage = cgImageOutVar {
            Task { @MainActor [weak self] in
                self?.previewFrame = cgImage
            }
        }
        
        // --- Throttle Heavy Processing (10 fps) ---
        let currentTime = CACurrentMediaTime()
        bgState.lock.lock()
        let lastTime = bgState.lastAnalysisTime
        if currentTime - lastTime < analysisInterval {
            bgState.lock.unlock()
            return
        }
        bgState.lastAnalysisTime = currentTime
        bgState.frameCount += 1
        bgState.lock.unlock()
        
        struct UncheckedBuffer: @unchecked Sendable { let buffer: CVPixelBuffer }
        let sBuffer = UncheckedBuffer(buffer: pixelBuffer)
        
        // 2. Run standard high-speed Vision tasks
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                // Safely create request within detached task thread bound context.
                let localBScanner = VNDetectBarcodesRequest()
                let localDScanner = VNDetectDocumentSegmentationRequest()
                let handler = VNImageRequestHandler(cvPixelBuffer: sBuffer.buffer, orientation: .up, options: [:])
                try handler.perform([localBScanner, localDScanner])
                
                let urls = localBScanner.results?.compactMap { $0.payloadStringValue }.compactMap { URL(string: $0) } ?? []
                let docs = localDScanner.results ?? []
                
                struct UncheckedObservations: @unchecked Sendable {
                    let items: [VNRectangleObservation]
                }
                let sendableDocs = UncheckedObservations(items: docs)
                
                await MainActor.run {
                    self.extractedBarcodeURLs = urls
                    self.detectedDocuments = sendableDocs.items
                }
            } catch {
                print("⚠️ [CameraManager] Native frame analysis failed: \(error)")
            }
        }
        
        let samService = self.samSegmentationService
        
        // 3. Run SAM 2.1 Segmentation (Pixel-Perfect AR Mask)
        if let sam = samService {
            Task.detached(priority: .utility) { [weak self] in
                do {
                    // This runs the CVPixelBuffer through the A-Series Neural Engine
                    let maskCGImage = try await sam.segment(pixelBuffer: sBuffer.buffer)
                    await MainActor.run { [weak self] in
                        self?.currentSegmentationMask = maskCGImage
                    }
                } catch {
                    // Suppress excessive logging if no subject is found
                }
            }
        }
        
        Task { @MainActor [weak self] in
            self?.onFrameCaptured?(sBuffer.buffer)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }
        guard let imageData = photo.fileDataRepresentation() else { return }
        
        // Extract depth data atomically with the photo
        var depthPNG: Data? = nil
        #if os(iOS)
        if let depthData = photo.depthData {
            let depthMap = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
            let ciImage = CIImage(cvPixelBuffer: depthMap)
            let context = CIContext()
            let colorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
            depthPNG = context.pngRepresentation(of: ciImage, format: .Lf, colorSpace: colorSpace)
            if depthPNG != nil {
                print("📐 Depth map captured: \(depthPNG!.count) bytes")
            }
        }
        #endif
        
        // Deliver both atomically
        Task { @MainActor [weak self] in
            self?.onPhotoCaptured?(imageData, depthPNG)
        }
    }
}
