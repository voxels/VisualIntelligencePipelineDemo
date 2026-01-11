import Foundation

public final class ReferencePayloadStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    
    public init(directoryURL: URL? = nil) throws {
        self.fileManager = FileManager.default
        if let directoryURL = directoryURL {
            self.directoryURL = directoryURL
        } else {
            // Default to Application Support/Payloads
            let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            self.directoryURL = appSupport.appendingPathComponent("Payloads", isDirectory: true)
        }
        
        try createDirectoryIfNeeded()
    }
    
    private func createDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
    
    public func savePayload(_ data: Data, id: String) throws -> String {
        let filename = "\(id).json.gz" // implied compression, though we might just write raw for now
        let fileURL = directoryURL.appendingPathComponent(filename)
        
        // In a real impl we might compress here, but for now just write
        try data.write(to: fileURL)
        return filename
    }
    
    public func loadPayload(filename: String) throws -> Data {
        let fileURL = directoryURL.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }
    
    public func deletePayload(filename: String) throws {
        let fileURL = directoryURL.appendingPathComponent(filename)
        try fileManager.removeItem(at: fileURL)
    }
    
    // Helper for App Group location
    public static func appGroupStore(groupID: String) throws -> ReferencePayloadStore {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw NSError(domain: "ReferencePayloadStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid App Group ID"])
        }
        let payloadsURL = containerURL.appendingPathComponent("Payloads", isDirectory: true)
        return try ReferencePayloadStore(directoryURL: payloadsURL)
    }
}
