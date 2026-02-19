//
//  APIKeyService.swift
//  DiverKit
//
//  Manages API keys for third-party services.
//  Keys are stored in the iOS Keychain with iCloud Keychain sync enabled,
//  so they propagate across the user's devices automatically.
//

import Foundation
import Security

/// Manages API keys stored in the iOS Keychain with iCloud sync.
/// Thread-safe: all Keychain operations are atomic at the OS level.
public final class APIKeyService: Sendable {
    
    /// Known API key identifiers for commerce services.
    public enum APIKey: String, CaseIterable, Sendable {
        case foursquare = "com.secretatomics.vi.foursquare"
        case reddit = "com.secretatomics.vi.reddit"
        case ifixit = "com.secretatomics.vi.ifixit"
    }
    
    public init() {}
    
    /// Store an API key in the Keychain (with iCloud sync).
    public func store(key: String, for identifier: APIKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identifier.rawValue,
            kSecAttrAccount as String: "api_key",
            kSecAttrSynchronizable as String: true,  // iCloud Keychain sync
            kSecValueData as String: Data(key.utf8)
        ]
        
        // Delete existing before storing
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw APIKeyError.keychainWriteFailed(status)
        }
    }
    
    /// Retrieve an API key from the Keychain.
    public func retrieve(for identifier: APIKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identifier.rawValue,
            kSecAttrAccount as String: "api_key",
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Delete an API key from the Keychain.
    public func delete(for identifier: APIKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identifier.rawValue,
            kSecAttrAccount as String: "api_key",
            kSecAttrSynchronizable as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// Check if an API key is configured.
    public func hasKey(for identifier: APIKey) -> Bool {
        retrieve(for: identifier) != nil
    }
    
    /// Get configuration status for all API keys.
    public func configurationStatus() -> [APIKey: Bool] {
        var status: [APIKey: Bool] = [:]
        for key in APIKey.allCases {
            status[key] = hasKey(for: key)
        }
        return status
    }
}

public enum APIKeyError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Keychain write failed with status: \(status)"
        }
    }
}
