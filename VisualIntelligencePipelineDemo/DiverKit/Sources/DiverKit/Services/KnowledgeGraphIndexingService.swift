import Foundation
import DiverShared

public protocol KnowledgeGraphIndexingService: Sendable {
    func indexItem(_ item: Item) async throws
    func indexItem(_ descriptor: DiverItemDescriptor) async throws
}
