//
//  MacIngestionService.swift
//  VisualIntelligenceMac
//
//  Handles all ingestion paths on macOS in priority order:
//
//  1. Drag & drop (images, URLs, files from Finder)         ← PRIMARY
//  2. Photos library picker (PHPickerViewController)        ← PRIMARY
//  3. File importer (NSOpenPanel for images/PDFs/HEIC)      ← PRIMARY
//  4. Continuity Camera (iPhone rear camera via AVFoundation)← CAMERA (preferred)
//  5. FaceTime / USB webcam fallback                        ← CAMERA (fallback, warn user)
//
//  NOTE: The FaceTime camera should never be the recommended path for
//  product/document capture — always prefer Continuity Camera or file import.
//

import AVFoundation
import UniformTypeIdentifiers
import AppKit
import SwiftUI

// MARK: - Camera Availability

public enum MacCameraKind: String {
    case continuityCamera = "Continuity Camera (iPhone)"
    case facetimeHD       = "FaceTime HD Camera"
    case usbWebcam        = "USB Webcam"
    case none             = "No Camera"
}

/// Describes an available camera device on macOS.
public struct MacCameraDevice: Identifiable {
    public let id: String        // AVCaptureDevice.uniqueID
    public let name: String
    public let kind: MacCameraKind
    public let avDevice: AVCaptureDevice

    /// True when this is an iPhone Continuity Camera.
    public var isContinuityCamera: Bool { kind == .continuityCamera }
}

// MARK: - MacIngestionService

@Observable
@MainActor
public final class MacIngestionService {

    // MARK: Published State

    public private(set) var availableCameras: [MacCameraDevice] = []
    public private(set) var preferredCamera: MacCameraDevice?
    public private(set) var cameraWarning: String?

    // MARK: Lifecycle

    public init() {
        discoverCameras()

        // Re-discover when devices connect/disconnect (e.g. iPhone plugged in)
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.discoverCameras() }
        }
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.discoverCameras() }
        }
    }

    // MARK: Camera Discovery

    public func discoverCameras() {
        var found: [MacCameraDevice] = []

        // Prefer Continuity Camera first (macOS 13+)
        #if compiler(>=5.9)
        let continuityDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        for dev in continuityDevices {
            found.append(MacCameraDevice(
                id: dev.uniqueID,
                name: dev.localizedName,
                kind: .continuityCamera,
                avDevice: dev
            ))
        }
        #endif

        // Built-in FaceTime HD
        let builtInSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        for dev in builtInSession.devices {
            found.append(MacCameraDevice(
                id: dev.uniqueID,
                name: dev.localizedName,
                kind: .facetimeHD,
                avDevice: dev
            ))
        }

        // External (USB) cameras
        let externalSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        for dev in externalSession.devices {
            // Skip Continuity Camera already captured above
            if !found.contains(where: { $0.id == dev.uniqueID }) {
                found.append(MacCameraDevice(
                    id: dev.uniqueID,
                    name: dev.localizedName,
                    kind: .usbWebcam,
                    avDevice: dev
                ))
            }
        }

        availableCameras = found

        // Set preferred camera — Continuity first, then USB, then FaceTime
        preferredCamera = found.first(where: { $0.kind == .continuityCamera })
            ?? found.first(where: { $0.kind == .usbWebcam })
            ?? found.first(where: { $0.kind == .facetimeHD })

        // Warn when only FaceTime is available
        if let cam = preferredCamera, cam.kind == .facetimeHD {
            cameraWarning = "Using your Mac's front camera — best with iPhone nearby for Continuity Camera"
        } else {
            cameraWarning = nil
        }
    }

    // MARK: File / URL Import Helpers

    public func openFilePicker(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .image, .jpeg, .png, .heic, .heif, .rawImage,
            .pdf, .plainText, .utf8PlainText
        ]
        panel.prompt = "Import"
        panel.message = "Select images, documents, or PDFs to add to your library"

        if panel.runModal() == .OK {
            completion(panel.urls)
        }
    }

    public func urlsFromPasteboard() -> [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil)?
            .compactMap { $0 as? URL } ?? []
    }
}

// MARK: - Drop Coordinator

/// Handles drag-and-drop of files, images, and URLs onto the Mac window.
public struct MacDropCoordinator: DropDelegate {
    public let onImages: ([NSImage]) -> Void
    public let onURLs: ([URL]) -> Void
    public let onFiles: ([URL]) -> Void

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [
            UTType.image, UTType.url, UTType.fileURL,
            UTType.pdf, UTType.plainText
        ])
    }

    public func performDrop(info: DropInfo) -> Bool {
        var handled = false

        // Images (dragged from Photos, Finder, browser)
        let imageProviders = info.itemProviders(for: [UTType.image])
        for provider in imageProviders {
            provider.loadObject(ofClass: NSImage.self) { image, _ in
                if let img = image as? NSImage {
                    Task { @MainActor in onImages([img]) }
                }
            }
            handled = true
        }

        // URLs (dragged from Safari, browser, Finder)
        let urlProviders = info.itemProviders(for: [UTType.url, UTType.fileURL])
        for provider in urlProviders {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    Task { @MainActor in
                        if url.isFileURL {
                            onFiles([url])
                        } else {
                            onURLs([url])
                        }
                    }
                }
            }
            handled = true
        }

        return handled
    }
}
