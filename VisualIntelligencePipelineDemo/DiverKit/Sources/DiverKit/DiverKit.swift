//
//  DiverKit.swift
//  DiverKit
//
//  Shared utilities for the Diver ecosystem.
//  Provides authentication, keychain services, and networking utilities.
//

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
