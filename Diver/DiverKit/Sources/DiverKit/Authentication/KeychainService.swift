//
//  KeychainService.swift
//  DiverKit
//
//  Generic keychain service for secure storage of tokens and credentials.
//  Extracted from Diver AuthManager and Know Maps AppleAuthenticationService.
//

import Foundation
import Security

/// Errors that can occur during keychain operations
public enum KeychainError: Error, Sendable {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)
    case unableToDelete(status: OSStatus)
    case dataConversionFailed
}

/// A generic keychain service for secure storage of sensitive data.
/// Thread-safe and Sendable for use in async contexts.
open class KeychainService: @unchecked Sendable {

    /// The service identifier used to namespace keychain items
    public let service: String

    /// The access group for sharing items across targets
    public let accessGroup: String?

    /// Creates a new KeychainService with the specified service identifier
    /// - Parameters:
    ///   - service: The service identifier
    ///   - accessGroup: Optional access group (e.g. "group.com.secretatomics.diver.shared")
    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// Stores data in the keychain
    /// - Parameters:
    ///   - key: The key to store the data under
    ///   - data: The data to store
    /// - Throws: KeychainError if the operation fails
    open func store(key: String, data: Data) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status: status)
        }
    }

    /// Stores a string value in the keychain
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    /// - Throws: KeychainError if the operation fails
    open func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        try store(key: key, data: data)
    }

    /// Stores an Encodable object in the keychain
    /// - Parameters:
    ///   - key: The key to store the object under
    ///   - object: The object to store
    ///   - encoder: The JSON encoder to use (defaults to ISO8601 date encoding)
    /// - Throws: KeychainError or encoding errors
    open func store<T: Encodable>(key: String, object: T, encoder: JSONEncoder? = nil) throws {
        let jsonEncoder = encoder ?? {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            return enc
        }()
        let data = try jsonEncoder.encode(object)
        try store(key: key, data: data)
    }

    /// Retrieves data from the keychain
    /// - Parameter key: The key to retrieve data for
    /// - Returns: The stored data, or nil if not found
    open func retrieve(key: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Retrieves a string value from the keychain
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The stored string, or nil if not found
    open func retrieveString(key: String) -> String? {
        guard let data = retrieve(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves and decodes a Decodable object from the keychain
    /// - Parameters:
    ///   - key: The key to retrieve the object for
    ///   - type: The type to decode to
    ///   - decoder: The JSON decoder to use (defaults to ISO8601 date decoding)
    /// - Returns: The decoded object, or nil if not found or decoding fails
    open func retrieve<T: Decodable>(key: String, as type: T.Type, decoder: JSONDecoder? = nil) -> T? {
        guard let data = retrieve(key: key) else { return nil }

        let jsonDecoder = decoder ?? {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return dec
        }()

        return try? jsonDecoder.decode(type, from: data)
    }

    /// Deletes an item from the keychain
    /// - Parameter key: The key to delete
    open func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes all items for this service from the keychain
    open func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Convenience Extensions

public extension KeychainService {
    /// Common keychain service identifiers
    enum ServiceIdentifier {
        public static let diver = "com.diver.auth"
        public static let diverKit = "com.diverkit.auth"
    }

    /// Common keychain keys
    enum Keys {
        public static let accessToken = "accessToken"
        public static let refreshToken = "refreshToken"
        public static let accessTokenExpiry = "accessTokenExpiry"
        public static let appleUserId = "appleUserId"
        public static let currentUser = "current_user"
        public static let diverLinkSecret = "diverLinkSecret"
    }
}
