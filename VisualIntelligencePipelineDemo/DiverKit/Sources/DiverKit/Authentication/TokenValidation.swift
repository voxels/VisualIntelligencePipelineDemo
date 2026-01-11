//
//  TokenValidation.swift
//  DiverKit
//
//  JWT token decoding and validation utilities.
//  Extracted from Diver AuthManager.
//

import Foundation

/// JWT claims structure for token validation
public struct JWTClaims: Codable, Sendable {
    /// Expiration timestamp (Unix time)
    public let exp: TimeInterval

    /// Subject (user ID)
    public let sub: String?

    /// Audience
    public let aud: String?

    /// Issuer
    public let iss: String?

    /// Issued at timestamp
    public let iat: TimeInterval?

    /// The expiration date derived from the exp claim
    public var expirationDate: Date {
        Date(timeIntervalSince1970: exp)
    }

    /// Whether the token has expired
    public var isExpired: Bool {
        Date() >= expirationDate
    }

    /// Time remaining until expiration
    public var timeUntilExpiration: TimeInterval {
        expirationDate.timeIntervalSinceNow
    }
}

/// Utility for validating and decoding JWT tokens
public enum TokenValidator {

    /// Decodes a JWT token and extracts its claims
    /// - Parameter token: The JWT token string
    /// - Returns: The decoded claims, or nil if decoding fails
    public static func decodeJWT(_ token: String) -> JWTClaims? {
        let segments = token.components(separatedBy: ".")
        guard segments.count > 1 else { return nil }

        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(JWTClaims.self, from: data)
    }

    /// Checks if a JWT token has expired
    /// - Parameter token: The JWT token string
    /// - Returns: True if the token is expired or invalid, false otherwise
    public static func isTokenExpired(_ token: String) -> Bool {
        guard let claims = decodeJWT(token) else { return true }
        return claims.isExpired
    }

    /// Gets the expiration date of a JWT token
    /// - Parameter token: The JWT token string
    /// - Returns: The expiration date, or nil if the token is invalid
    public static func getExpirationDate(_ token: String) -> Date? {
        guard let claims = decodeJWT(token) else { return nil }
        return claims.expirationDate
    }

    /// Checks if a token will expire within a given time interval
    /// - Parameters:
    ///   - token: The JWT token string
    ///   - interval: The time interval to check against
    /// - Returns: True if the token will expire within the interval
    public static func willExpireSoon(_ token: String, within interval: TimeInterval = 300) -> Bool {
        guard let claims = decodeJWT(token) else { return true }
        return claims.timeUntilExpiration < interval
    }
}

// MARK: - Token Response

/// Standard OAuth token response structure
public struct TokenResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String?
    public let tokenType: String?
    public let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }

    public init(accessToken: String, refreshToken: String, idToken: String? = nil, tokenType: String? = "Bearer", expiresIn: Int? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
    }
}
