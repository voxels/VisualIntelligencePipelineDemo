//
//  EdgeNodeInstallService.swift
//  VisualIntelligenceMac
//
//  Manages registration of the "Visual Intelligence Node" Login Item helper
//  using SMAppService. The helper is embedded inside the main app bundle at:
//
//  VisualIntelligence.app/Contents/Library/LoginItems/
//      VisualIntelligenceNode.app
//
//  Bundle ID convention required by Apple:
//    Parent:  com.secretatomics.visualintelligence.mac
//    Helper:  com.secretatomics.visualintelligence.node   ← child of parent
//
//  No admin password, no privilege escalation — fully App Store compatible.
//

import Foundation
import ServiceManagement
import Observation
import AppKit

// MARK: - Install Status

public enum EdgeNodeInstallStatus: String {
    case notInstalled   = "Not Installed"
    case installing     = "Installing…"
    case running        = "Running"
    case requiresApproval = "Approval Required"
    case error          = "Error"
}

// MARK: - EdgeNodeInstallService

/// Registers and monitors the Visual Intelligence Node login item helper.
@Observable
@MainActor
public final class EdgeNodeInstallService {

    // MARK: State

    public private(set) var installStatus: EdgeNodeInstallStatus = .notInstalled
    public private(set) var lastError: String?

    /// True once the user has been shown the install prompt (regardless of choice).
    public var hasPromptedUser: Bool {
        get { UserDefaults.standard.bool(forKey: "vi.edgenode.hasPrompted") }
        set { UserDefaults.standard.set(newValue, forKey: "vi.edgenode.hasPrompted") }
    }

    public var isRunning: Bool {
        installStatus == .running
    }


    // MARK: Constants


    /// Must match PRODUCT_BUNDLE_IDENTIFIER of the VisualIntelligenceMacEdgeNode target.
    private static let nodeHelperBundleID = "com.secretatomics.visualintelligence.mac.edgenode"

    private var smService: SMAppService {
        SMAppService.loginItem(identifier: Self.nodeHelperBundleID)
    }

    // MARK: Lifecycle

    public init() {
        guard !isRunningFromDerivedData else {
            installStatus = .notInstalled
            return
        }
        refresh()
    }

    // MARK: Public API

    /// Install and register the Node as a Login Item.
    /// Shows in System Settings → General → Login Items as "Visual Intelligence Node".
    public func install() {
        print("🔧 [EdgeNode] install() called — status: \(installStatus), isDerivedData: \(isRunningFromDerivedData)")
        installStatus = .installing
        lastError = nil

        if isRunningFromDerivedData {
            launchEdgeDaemonDirect()
            return
        }

        do {
            print("🔧 [EdgeNode] Calling smService.register()…")
            try smService.register()
            print("🔧 [EdgeNode] register() succeeded")
            refresh()
        } catch let error as NSError {
            print("🔧 [EdgeNode] register() failed: \(error)")
            installStatus = .error
            if error.code == 22 {
                lastError = "Helper not found inside the app bundle. Install Visual Intelligence from the App Store to use this feature."
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    /// Dev-only: launch the EdgeNode helper embedded in this app bundle.
    /// In production SMAppService handles this; in dev we launch directly.
    private func launchEdgeDaemonDirect() {
        // Primary: embedded via Copy Files build phase (production + full scheme build)
        let loginItemsURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/VisualIntelligenceMacEdgeNode.app")

        // Fallback: sibling in the same Products/Debug folder (when building EdgeNode target
        // separately without the Copy Files phase running — common in partial dev builds)
        let siblingURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("VisualIntelligenceMacEdgeNode.app")

        let helperURL: URL
        if FileManager.default.fileExists(atPath: loginItemsURL.path) {
            helperURL = loginItemsURL
        } else if FileManager.default.fileExists(atPath: siblingURL.path) {
            helperURL = siblingURL
        } else {
            print("🔧 [EdgeNode] Helper not found at:\n  \(loginItemsURL.path)\n  \(siblingURL.path)")
            installStatus = .notInstalled
            lastError = "Build the VisualIntelligenceMac scheme in Xcode (⌘B) — both VisualIntelligenceMac and VisualIntelligenceMacEdgeNode targets must build."
            return
        }

        print("🔧 [EdgeNode] Launching \(helperURL.path)")
        NSWorkspace.shared.openApplication(
            at: helperURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            DispatchQueue.main.async {
                if let error {
                    print("🔧 [EdgeNode] Launch failed: \(error)")
                    self.installStatus = .error
                    self.lastError = error.localizedDescription
                } else {
                    print("🔧 [EdgeNode] EdgeNode launched ✅")
                    self.installStatus = .running
                    self.lastError = nil
                }
            }
        }
    }




    private var isRunningFromDerivedData: Bool {
        Bundle.main.bundlePath.contains("DerivedData")
    }

    /// Unregister the Login Item (does not delete the binary).
    public func uninstall() {
        do {
            try smService.unregister()
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Open System Settings → General → Login Items.
    /// Call this when status is `.requiresApproval`.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Re-query SMAppService for current status.
    public func refresh() {
        switch smService.status {
        case .notRegistered, .notFound:
            installStatus = .notInstalled
        case .enabled:
            installStatus = .running
        case .requiresApproval:
            installStatus = .requiresApproval
        @unknown default:
            installStatus = .notInstalled
        }
    }
}
