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
public final class CameraManager: NSObject, ObservableObject {
    @Published public var isReady = false
    @Published public var session = AVCaptureSession()
    @Published public var isRecording = false
    
    private let sessionQueue = DispatchQueue(label: "com.diver.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    public var onFrameCaptured: ((CVPixelBuffer) -> Void)?
    public var onPhotoCaptured: ((Data) -> Void)?
    
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
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
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
                onPhotoCaptured?(data)
            }
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
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
        onPhotoCaptured?(imageData)
    }
}
