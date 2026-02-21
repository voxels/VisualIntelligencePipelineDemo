//
//  APIKeyService.swift
//  DiverKit
//
//  Manages API keys for third-party services.
//  Keys are stored in the iCloud.com.secretatomics.knowmaps.Keys CloudKit
//  container (private database), so they sync across the user's devices
//  automatically via CloudKit.
//

import Foundation
import CloudKit

/// Manages API keys stored in a dedicated CloudKit container.
/// Uses the `iCloud.com.secretatomics.knowmaps.Keys` private database.
/// Thread-safe: all CloudKit operations are atomic.
public final class APIKeyService: Sendable {
    
    /// Known API key identifiers for commerce and affiliate services.
    public enum APIKey: String, CaseIterable, Sendable {
        case foursquare = "com.secretatomics.vi.foursquare"
        case reddit = "com.secretatomics.vi.reddit"
        case ifixit = "com.secretatomics.vi.ifixit"
        // Affiliate program tags (stored via Settings > API Keys)
        case amazonAssociates = "com.secretatomics.vi.affiliate.amazon"
        case ebayPartnerNetwork = "com.secretatomics.vi.affiliate.ebay"
        case targetPartners = "com.secretatomics.vi.affiliate.target"
        case bestBuyAffiliate = "com.secretatomics.vi.affiliate.bestbuy"
        case thriveMarketReferral = "com.secretatomics.vi.affiliate.thrive"
    }
    
    /// CloudKit container identifier for key storage.
    private static let containerID = "iCloud.com.secretatomics.knowmaps.Keys"
    
    /// CloudKit record type for API keys.
    private static let recordType = "APIKey"
    
    /// The CloudKit container for key storage.
    private let container: CKContainer
    
    /// The private database in the Keys container.
    private var database: CKDatabase { container.privateCloudDatabase }
    
    /// In-memory cache for fast synchronous reads.
    /// Populated on first fetch and updated on store/delete.
    /// Thread-safe: NSCache is internally synchronized.
    nonisolated(unsafe) private let cache = NSCache<NSString, NSString>()
    
    public init() {
        self.container = CKContainer(identifier: Self.containerID)
    }
    
    // MARK: - Async API (Primary)
    
    /// Store an API key in CloudKit.
    public func store(key: String, for identifier: APIKey) async throws {
        let recordID = CKRecord.ID(recordName: identifier.rawValue)
        
        // Fetch existing record or create new one
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        
        record["value"] = key as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        
        try await database.save(record)
        
        // Update cache
        cache.setObject(key as NSString, forKey: identifier.rawValue as NSString)
    }
    
    /// Retrieve an API key from CloudKit.
    public func retrieve(for identifier: APIKey) async throws -> String? {
        // Check cache first
        if let cached = cache.object(forKey: identifier.rawValue as NSString) {
            return cached as String
        }
        
        let recordID = CKRecord.ID(recordName: identifier.rawValue)
        
        do {
            let record = try await database.record(for: recordID)
            let value = record["value"] as? String
            
            // Cache the result
            if let value {
                cache.setObject(value as NSString, forKey: identifier.rawValue as NSString)
            }
            
            return value
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
    
    /// Synchronous retrieve — returns cached value or nil.
    /// Call `prefetchKeys()` on app launch to populate the cache.
    public func retrieve(for identifier: APIKey) -> String? {
        return cache.object(forKey: identifier.rawValue as NSString) as? String
    }
    
    /// Delete an API key from CloudKit.
    public func delete(for identifier: APIKey) async throws {
        let recordID = CKRecord.ID(recordName: identifier.rawValue)
        try await database.deleteRecord(withID: recordID)
        cache.removeObject(forKey: identifier.rawValue as NSString)
    }
    
    /// Delete synchronous variant (fire-and-forget).
    public func delete(for identifier: APIKey) {
        cache.removeObject(forKey: identifier.rawValue as NSString)
        Task {
            try? await database.deleteRecord(withID: CKRecord.ID(recordName: identifier.rawValue))
        }
    }
    
    /// Check if an API key is configured (cached check).
    public func hasKey(for identifier: APIKey) -> Bool {
        cache.object(forKey: identifier.rawValue as NSString) != nil
    }
    
    /// Prefetch all keys from CloudKit into the in-memory cache.
    /// Call this on app launch to enable synchronous `retrieve(for:)`.
    public func prefetchKeys() async {
        for key in APIKey.allCases {
            if let value = try? await retrieve(for: key) {
                cache.setObject(value as NSString, forKey: key.rawValue as NSString)
            }
        }
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
    case cloudKitError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .cloudKitError(let error):
            return "CloudKit key storage failed: \(error.localizedDescription)"
        }
    }
}
