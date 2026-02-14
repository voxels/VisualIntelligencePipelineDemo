import Foundation
import SwiftData
import DiverShared

@Model
public final class LocalInput: Identifiable {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now
    public var url: String?
    public var text: String?
    public var source: String?
    public var inputType: String = "web"
    public var rawPayload: Data?
    
    /// Session ID from the original descriptor — survives crash/cancellation recovery
    public var sessionID: String?
    /// Context tags (purposes) from the original descriptor
    public var purposes: [String] = []
    /// Full serialized DiverItemDescriptor for crash recovery
    public var descriptorJSON: Data?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        url: String? = nil,
        text: String? = nil,
        source: String? = nil,
        inputType: String = "web",
        rawPayload: Data? = nil,
        sessionID: String? = nil,
        purposes: [String] = [],
        descriptorJSON: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.url = url
        self.text = text
        self.source = source
        self.inputType = inputType
        self.rawPayload = rawPayload
        self.sessionID = sessionID
        self.purposes = purposes
        self.descriptorJSON = descriptorJSON
    }
}

