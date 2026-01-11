import Foundation
import DiverShared

/// Agent [DATA] - Responsible for Link Generation and Store Integration
public struct DiverLinkGenerator {
    public let store: DiverQueueStore
    private let secret: Data
    
    public init(store: DiverQueueStore, secret: Data) {
        self.store = store
        self.secret = secret
    }
    
    public func createAndSaveLink(from url: URL, title: String? = nil, labels: [String] = []) throws -> URL {
        // 1. Wrap the URL
        let payload = DiverLinkPayload(url: url, title: title)
        let wrappedURL = try DiverLinkWrapper.wrap(
            url: url,
            secret: secret,
            payload: payload,
            includePayload: true
        )
        
        // 2. Enqueue in the store
        let descriptor = DiverItemDescriptor(
            id: DiverLinkWrapper.id(for: url),
            url: url.absoluteString,
            title: title ?? (url.host ?? url.absoluteString),
            categories: labels
        )
        
        let queueItem = DiverQueueItem(
            action: "save",
            descriptor: descriptor,
            source: "visual-intelligence"
        )
        
        try store.enqueue(queueItem)
        
        return wrappedURL
    }
}
