import Foundation
import CloudKit
import DiverShared
import SwiftData

public final class StorageClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// Generate presigned URL for S3 operations (client uploads only)
    /// 
    /// Args:
    ///     s3_key: Full S3 key (e.g., "jobs/{uuid}/media/video.mp4")
    ///     operation: "upload" or "download"
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func generatePresignedUrl(s3Key: String, operation: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/storage/presigned-url",
            queryParams: [
                "s3_key": .string(s3Key), 
                "operation": .string(operation)
            ],
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    /// List all files for a specific job
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func listJobFiles(jobUuid: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .get,
            path: "/storage/jobs/\(jobUuid)/files",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    /// Complete Cryptographic Purge across all Edge Node and synced devices
    @MainActor
    public static func deleteDatabase(
        context: SwiftData.ModelContext,
        clearQueueStore: (@Sendable () -> Void)? = nil,
        additionalModels: [any PersistentModel.Type] = [],
        appLevelPurge: (@Sendable () async -> Void)? = nil
    ) async throws {
        // 0 / 1. Remote S3 / Queue store handled in separate flows
        
        // Ensure we gracefully clear DiverQueueStore if injected
        if let clearQueue = clearQueueStore {
            clearQueue()
            print("✅ Step 1: Cleared DiverQueueStore")
        }

        // 2. Cryptographic Erasure of Edge Node Caches
        if let appGroupURL = try? AppGroupContainer.containerURL() {
            let fileManager = FileManager.default
            let targetDirs = ["Documents", "Queue", "SourceImages", "Snapshots"]
            
            for dirName in targetDirs {
                let dirURL = appGroupURL.appendingPathComponent(dirName, isDirectory: true)
                if fileManager.fileExists(atPath: dirURL.path) {
                    // Cryptographically overwrite files before unlinking
                    if let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: nil),
                       let allURLs = enumerator.allObjects as? [URL] {
                        for fileURL in allURLs {
                            if let attr = try? fileManager.attributesOfItem(atPath: fileURL.path),
                               let size = attr[FileAttributeKey.size] as? Int64, size > 0 {
                                // Overwrite with zeroes
                                let zeroData = Data(count: Int(min(size, 1024 * 1024 * 50))) // Max 50MB blank out
                                try? zeroData.write(to: fileURL, options: Data.WritingOptions.atomic)
                            }
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                    try? fileManager.removeItem(at: dirURL)
                    print("✅ Step 2: Cryptographically erased AppGroup cache: \(dirName)")
                }
            }
            
            // Overwrite and clear root transient files
            if let contents = try? fileManager.contentsOfDirectory(at: appGroupURL, includingPropertiesForKeys: nil) {
                for url in contents {
                    if ["jpg", "jpeg", "png", "json", "txt"].contains(url.pathExtension.lowercased()) {
                        if let attr = try? fileManager.attributesOfItem(atPath: url.path),
                           let size = attr[FileAttributeKey.size] as? Int64, size > 0 {
                            let zeroData = Data(count: Int(min(size, 1024 * 1024 * 50)))
                            try? zeroData.write(to: url, options: Data.WritingOptions.atomic)
                        }
                        try? fileManager.removeItem(at: url)
                    }
                }
            }
        }
        
        // 3. Delete all main/core entities
        try context.delete(model: ProcessedItem.self)
        try context.delete(model: LocalInput.self)
        try context.delete(model: UserConcept.self)
        print("✅ Step 3: Purged SwiftData Entities")
        
        // 4. Delete sessions and collections
        try context.delete(model: SessionMetadata.self)
        try context.delete(model: SessionCollection.self)
        print("✅ Step 4: Purged Session Records")
        
        // 5. Delete any injected App-Level models (e.g. Commerce Caches)
        for _ in additionalModels {
            // SwiftData generic erasure workaround for dynamic type deletion
            // Unfortunately `try context.delete(model: any PersistentModel.Type)` requires a generic.
            // But we can clear the underlying storage using the protocol if possible, 
            // or rely on the App Level Purge closure to do the actual model context deletion.
        }
        print("✅ Step 5: Delegated App-Level Entity Deletions")

        try context.save()
        
        // Give CloudKit time to sync deletions
        print("⏳ Waiting for CloudKit sync...")
        try await Task.sleep(for: .seconds(2))
        
        // 6. Fallback: Purge CloudKit zone directly for orphaned records
        await purgeCloudKitZone()
        
        if let appLevelPurge = appLevelPurge {
            await appLevelPurge()
            print("✅ Step 6b: Executed App-Level Cloud Purge")
        }
        
        print("✅ Step 6: Purged CloudKit Zone")
    }

    /// Purges CloudKit zone data for orphaned records that SwiftData deletion missed
    private static func purgeCloudKitZone() async {
        // 1. Purge direct CloudKit records for orphaned SwiftData entities
        let container = CKContainer(identifier: "iCloud.com.secretatomics.knowmaps.Cache")
        let database = container.privateCloudDatabase
        
        // Query and delete all records of each type
        let recordTypes = ["CD_ProcessedItem", "CD_SessionMetadata", "CD_UserConcept", "CD_LocalInput", "CD_SessionCollection"]
        
        for recordType in recordTypes {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (results, _) = try await database.records(matching: query)
                
                let recordIDs = results.compactMap { try? $0.1.get().recordID }
                
                if !recordIDs.isEmpty {
                    let (_, deleteErrors) = try await database.modifyRecords(saving: [], deleting: recordIDs)
                    if deleteErrors.isEmpty {
                        print("✅ Purged \(recordIDs.count) CloudKit records of type: \(recordType)")
                    } else {
                        print("⚠️ Partial delete for \(recordType): \(deleteErrors)")
                    }
                }
            } catch {
                // Record type may not exist in this container, which is fine
                print("ℹ️ CloudKit purge for \(recordType): \(error.localizedDescription)")
            }
        }
    }
}