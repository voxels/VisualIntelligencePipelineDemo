//  DiverKit.swift
//  DiverKit
//
//  Shared utilities for the Diver ecosystem.
//  Provides authentication, keychain services, and networking utilities.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Define custom UTTypes for Diver objects to prevent ambiguity
public extension UTType {
    static var diverItem: UTType {
        UTType(exportedAs: "com.secretatomics.diver.item")
    }
    static var diverSession: UTType {
        UTType(exportedAs: "com.secretatomics.diver.session")
    }
}

/// Sendable DTO for transferring a ProcessedItem via drag and drop
public struct ItemTransfer: Codable, Transferable, Sendable {
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diverItem)
    }
}

/// Sendable DTO for transferring a SessionMetadata via drag and drop
public struct SessionTransfer: Codable, Transferable, Sendable {
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diverSession)
    }
}

import Foundation

/// DiverKit version information
public enum DiverKitInfo {
    public static let version = "1.0.0"
    public static let name = "DiverKit"
}

/*
 DiverKit Public API:

 Authentication:
 - AuthenticationState: Enum representing auth state (authenticated, unauthenticated, etc.)
 - AppleAuthenticationService: Apple Sign-In service with token management
 - KeychainService: Secure keychain storage for tokens and credentials
 - TokenValidator: JWT token decoding and validation
 - TokenResponse: OAuth token response structure

 Networking:
 - ClientError: Unified error types for network operations
 - APIErrorResponse: Standard API error response structure

 Utilities:
 - JSONEncoder.diverKit: Pre-configured JSON encoder
 - JSONDecoder.diverKit: Pre-configured JSON decoder
 */
