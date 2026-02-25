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
        SessionMetadata.self,
        SessionCollection.self,
        OwnedProduct.self,
        ScoreSnapshot.self,
        EthicalPolicySettings.self,
        PersonVector.self
    ]

    public init(schema: Schema, configurations: [ModelConfiguration]) throws {
        do {
            self.container = try ModelContainer(
                for: schema,
                configurations: configurations
            )
        } catch {
            DiverLogger.storage.critical("DiverDataStore: Failed to create ModelContainer with custom configurations: \(error.localizedDescription)")
            DiverLogger.storage.warning("DiverDataStore: Attempting fallback to in-memory container")
            do {
                self.container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                DiverLogger.storage.critical("DiverDataStore: SwiftData is catastrophically corrupted. In-memory fallback failed: \(error.localizedDescription)")
                throw error
            }
        }
    }

    public init(container: ModelContainer) {
        self.container = container
    }
    
    // Note: SwiftData + CloudKit sync is automatic when the app's entitlements
    // include a CloudKit container identifier. NSPersistentHistoryTrackingKey and
    // remote change notifications are enabled internally by ModelContainer.
    // @Query views auto-refresh via NSManagedObjectContextObjectsDidChange.
    // Pull-to-refresh triggers modelContext.save() to push local changes immediately.
    
    public func generateAgenticContextString(limit: Int = 30) -> String {
        var sections: [String] = []
        
        // --- Section 1: Recent Library Items ---
        let descriptor = FetchDescriptor<ProcessedItem>()
        if let items = try? mainContext.fetch(descriptor), !items.isEmpty {
            let recentText = items
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(limit)
                .compactMap { item -> String? in
                    var components: [String] = []
                    
                    let title = item.title ?? "Untitled"
                    components.append("Title: \(title)")
                    
                    if let location = item.placeContext?.name, !location.isEmpty {
                        components.append("Location: \(location)")
                    }
                    
                    if let weather = item.weatherContext?.condition, !weather.isEmpty {
                        components.append("Weather: \(weather)")
                    }
                    
                    if let activity = item.activityContext?.type, !activity.isEmpty {
                        components.append("Activity: \(activity.capitalized)")
                    }
                    
                    let tags = Array(Set(item.visualTags + item.tags + item.categories + item.purposes)).sorted()
                    if !tags.isEmpty {
                        components.append("Tags: \(tags.joined(separator: ", "))")
                    }
                    
                    let text = item.summary ?? item.transcription ?? ""
                    if !text.isEmpty {
                        components.append("Details: \(String(text.prefix(200)))")
                    }
                    
                    if components.isEmpty { return nil }
                    return components.joined(separator: " | ")
                }
                .joined(separator: "\n---\n")
            
            if !recentText.isEmpty {
                sections.append("Recent Library Items:\n\(recentText)")
            }
        }
        
        // --- Section 2: User Interests (UserConcept weights) ---
        let conceptDescriptor = FetchDescriptor<UserConcept>(
            sortBy: [SortDescriptor(\.weight, order: .reverse)]
        )
        if let concepts = try? mainContext.fetch(conceptDescriptor), !concepts.isEmpty {
            let conceptEntries = concepts.prefix(20).map { concept in
                var entry = "\(concept.name) (weight: \(String(format: "%.1f", concept.weight)))"
                if !concept.definition.isEmpty {
                    entry += " — \(String(concept.definition.prefix(80)))"
                }
                return "- \(entry)"
            }.joined(separator: "\n")
            sections.append("User Interests & Concepts:\n\(conceptEntries)")
        }
        
        // --- Section 3: Owned Products ---
        let productDescriptor = FetchDescriptor<OwnedProduct>(
            sortBy: [SortDescriptor(\.acquiredAt, order: .reverse)]
        )
        if let products = try? mainContext.fetch(productDescriptor), !products.isEmpty {
            let productEntries = products.prefix(15).map { product in
                var entry = product.productName
                if let brand = product.brand, !brand.isEmpty { entry += " by \(brand)" }
                if let category = product.category, !category.isEmpty { entry += " [\(category)]" }
                entry += " (\(product.status.rawValue))"
                if let score = product.recommendedScore {
                    entry += " score: \(String(format: "%.0f%%", score * 100))"
                }
                return "- \(entry)"
            }.joined(separator: "\n")
            sections.append("Owned Products:\n\(productEntries)")
        }
        
        // --- Section 4: Commerce Scoring Intelligence ---
        var snapshotDescriptor = FetchDescriptor<ScoreSnapshot>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        snapshotDescriptor.fetchLimit = 30
        if let snapshots = try? mainContext.fetch(snapshotDescriptor), !snapshots.isEmpty {
            // Group by productID and keep only the latest per product
            var latestByProduct: [String: ScoreSnapshot] = [:]
            for snapshot in snapshots {
                if latestByProduct[snapshot.productID] == nil {
                    latestByProduct[snapshot.productID] = snapshot
                }
            }
            
            let scoreEntries = latestByProduct.values
                .sorted { ($0.compositeScore ?? 0) > ($1.compositeScore ?? 0) }
                .prefix(10)
                .map { snapshot in
                    var entry = snapshot.productName
                    if let brand = snapshot.brand { entry += " (\(brand))" }
                    if let score = snapshot.compositeScore {
                        entry += " — composite: \(String(format: "%.0f%%", score * 100))"
                    }
                    let strategies = snapshot.strategyScores
                        .map { "\($0.strategyID): \(String(format: "%.0f%%", $0.score * 100))" }
                        .joined(separator: ", ")
                    if !strategies.isEmpty { entry += " [\(strategies)]" }
                    return "- \(entry)"
                }.joined(separator: "\n")
            
            if !scoreEntries.isEmpty {
                sections.append("Commerce Score Intelligence:\n\(scoreEntries)")
            }
        }
        
        return sections.isEmpty ? "" : sections.joined(separator: "\n\n")
    }

    public init(types: [any PersistentModel.Type] = DiverDataStore.coreTypes, inMemory: Bool = false, forAppGroup: Bool = true) throws {
        let schema = Schema(types)
        
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if forAppGroup {
            do {
                let appGroupURL = try AppGroupContainer.containerURL()
                // Ensure the base AppGroup directory requires full device unlock to access
                try AppGroupContainer.ensureProtectedDirectory(at: appGroupURL)
                
                let storeURL = try AppGroupContainer.dataStoreURL()
                configuration = ModelConfiguration(schema: schema, url: storeURL)
            }
            catch {
                DiverLogger.storage.error("DiverDataStore: Failed to get App Group URL or create ModelConfiguration: \(error.localizedDescription). Falling back to non-App Group store.")
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            }
        } else {
            // Default to non-App Group persistent store if not inMemory and not forAppGroup
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            self.container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            DiverLogger.storage.critical("DiverDataStore: Failed to create primary ModelContainer: \(error.localizedDescription)")
            DiverLogger.storage.warning("DiverDataStore: Falling back to in-memory configuration.")
            do {
                self.container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                throw error
            }
        }
    }
    
    // MARK: - Helper Queries
    
    public func fetchLastSession() -> SessionMetadata? {
        var descriptor = FetchDescriptor<SessionMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? mainContext.fetch(descriptor).first
    }
}
