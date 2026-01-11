import Foundation
import SwiftData
import DiverShared
import CoreData // Explicitly import CoreData

@MainActor
public final class UnifiedDataManager {
    public static var shared: UnifiedDataManager?

    public let store: DiverDataStore
    
    public var container: ModelContainer {
        store.container
    }

    public var mainContext: ModelContext {
        store.mainContext
    }

    // Public initializer for testability and flexible setup
    public init(inMemory: Bool = false, forAppGroup: Bool = true) {
        self.store = DiverDataStore(types: DiverDataStore.coreTypes, inMemory: inMemory, forAppGroup: forAppGroup)
    }
    
    // Allow wrapping an existing store
    public init(store: DiverDataStore) {
        self.store = store
    }
}
