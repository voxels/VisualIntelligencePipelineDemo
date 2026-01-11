import Foundation
import SwiftData

@Model
public final class LocalInput: Identifiable {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now
    public var url: String?
    public var text: String?
    public var source: String?
    public var inputType: String = "web"
    public var rawPayload: Data?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        url: String? = nil,
        text: String? = nil,
        source: String? = nil,
        inputType: String = "web",
        rawPayload: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.url = url
        self.text = text
        self.source = source
        self.inputType = inputType
        self.rawPayload = rawPayload
    }
}

