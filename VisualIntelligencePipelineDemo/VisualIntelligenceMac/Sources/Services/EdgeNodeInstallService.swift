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

    /// Must match PRODUCT_BUNDLE_IDENTIFIER in the Node helper target.
    private static let nodeHelperBundleID = "com.secretatomics.visualintelligence.mac.edgenode.helper"

    private var smService: SMAppService {
        SMAppService.loginItem(identifier: Self.nodeHelperBundleID)
    }

    // MARK: Lifecycle

    public init() {
        refresh()
    }

    // MARK: Public API

    /// Install and register the Node as a Login Item.
    /// Shows in System Settings → General → Login Items as "Visual Intelligence Node".
    public func install() {
        installStatus = .installing
        lastError = nil

        do {
            try smService.register()
            // Status might not update immediately, so we refresh again after a short delay
            refresh()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                refresh()
            }
        } catch {
            print("❌ EdgeNodeInstallService: Registration failed: \(error)")
            installStatus = .error
            lastError = error.localizedDescription
        }
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
