//
//  AuthenticationState.swift
//  DiverKit
//
//  Unified authentication state enum for the Diver ecosystem.
//

import Foundation

/// Represents the current authentication state of the application
public enum AuthenticationState: Sendable, Equatable {
    /// User is not authenticated
    case unauthenticated

    /// Authentication is in progress
    case authenticating

    /// User is authenticated and token is valid
    case authenticated

    /// Validating existing credentials with the server
    case validating

    /// Authentication token has expired
    case expired

    /// An error occurred during authentication
    case error(String)

    // MARK: - Equatable

    public static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
        switch (lhs, rhs) {
        case (.unauthenticated, .unauthenticated),
             (.authenticating, .authenticating),
             (.authenticated, .authenticated),
             (.validating, .validating),
             (.expired, .expired):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Convenience Properties

public extension AuthenticationState {
    /// Whether the user is currently authenticated
    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    /// Whether authentication is currently in progress
    var isAuthenticating: Bool {
        switch self {
        case .authenticating, .validating:
            return true
        default:
            return false
        }
    }

    /// Whether an error has occurred
    var hasError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    /// The error message, if any
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}
