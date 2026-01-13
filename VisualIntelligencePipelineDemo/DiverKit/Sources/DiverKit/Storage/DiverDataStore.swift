import Foundation
import SwiftData
import DiverShared
import CoreData

@MainActor
public final class DiverDataStore {
    public let container: ModelContainer
    public var mainContext: ModelContext {
        container.mainContext
    }

    /// Core Diver definitions that should always be included
    public static let coreTypes: [any PersistentModel.Type] = [
        LocalInput.self,
        ProcessedItem.self,
        UserConcept.self,
        DiverSession.self
    ]

    public init(schema: Schema, configurations: [ModelConfiguration]) {
        do {
            self.container = try ModelContainer(for: schema, configurations: configurations)
        } catch {
            fatalError("DiverDataStore: Failed to create ModelContainer with custom configurations: \(error)")
        }
    }

    public init(container: ModelContainer) {
        self.container = container
    }

    public init(types: [any PersistentModel.Type] = DiverDataStore.coreTypes, inMemory: Bool = false, forAppGroup: Bool = true) {
        let schema = Schema(types)
        
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if forAppGroup {
            do {
                let appGroupURL = try AppGroupContainer.dataStoreURL()
                configuration = ModelConfiguration(schema: schema, url: appGroupURL)
            }
            catch {
                fatalError("DiverDataStore: Failed to get App Group URL or create ModelConfiguration: \(error)")
            }
        } else {
            // Default to non-App Group persistent store if not inMemory and not forAppGroup
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            self.container = try ModelContainer(for: schema, configurations: [configuration])

        } catch {
            fatalError("DiverDataStore: Failed to create ModelContainer: \(error)")
        }
    }
}
