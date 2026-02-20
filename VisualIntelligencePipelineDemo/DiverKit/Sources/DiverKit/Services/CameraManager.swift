import Foundation
import AVFoundation
import Vision
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Agent [CORE] - Responsible for Camera Session and Intent Launch Foundation
/// Safety: @unchecked Sendable is correct — serial `sessionQueue` guards AVFoundation work,
/// `@Published` properties are only mutated via DispatchQueue.main.async.
public final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published public var isReady = false
    @Published public var session = AVCaptureSession()
    @Published public var isRecording = false
    
    private let sessionQueue = DispatchQueue(label: "com.diver.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    public var onFrameCaptured: ((CVPixelBuffer) -> Void)?
    /// Callback delivers (imageData, depthData?) atomically so depth is always paired with the correct photo
    public var onPhotoCaptured: ((Data, Data?) -> Void)?
    
    public override init() {
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
             
             sessionQueue.async { [weak self] in
                 self?.session.startRunning()
                 DispatchQueue.main.async {
                     self?.isReady = true
                 }
             }
        }
    }
    
    public func stopSession() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
                DispatchQueue.main.async {
                    self?.isReady = false
                }
            }
        }
    }
    
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
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
        settings.isHighResolutionPhotoEnabled = true
        
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
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrameCaptured?(pixelBuffer)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
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
        onPhotoCaptured?(imageData, depthPNG)
    }
}
