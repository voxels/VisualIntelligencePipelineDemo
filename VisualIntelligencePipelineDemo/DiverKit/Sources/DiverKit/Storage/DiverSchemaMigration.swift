//
//  DiverSchemaMigration.swift
//  DiverKit
//
//  VersionedSchema and SchemaMigrationPlan for the Diver data model.
//  All migrations must be lightweight to preserve CloudKit sync.
//
//  V1: Current schema baseline (7 models) — snapshot as of Feb 2026.
//      The database already has all 7 models via implicit lightweight
//      migration. This versioning formalizes the current state so future
//      schema changes have a safe migration path.
//
//  Usage: NOT yet wired into DiverDataStore. When ready, pass
//         migrationPlan: DiverMigrationPlan.self to ModelContainer.
//

import Foundation
import SwiftData

// MARK: - Schema V1 (Current Baseline)

/// Current Diver schema with all 7 models.
/// This is a snapshot of the existing on-disk schema — no migration needed.
/// Future schema changes should add a V2 and a lightweight migration stage.
public enum DiverSchemaV1: VersionedSchema {
    nonisolated(unsafe) public static var versionIdentifier = Schema.Version(1, 0, 0)
    
    public static var models: [any PersistentModel.Type] {
        [
            LocalInput.self,
            ProcessedItem.self,
            UserConcept.self,
            SessionMetadata.self,
            SessionCollection.self,
            OwnedProduct.self,
            ScoreSnapshot.self
        ]
    }
}

// MARK: - Migration Plan

/// Migration plan for the Diver data model.
/// Currently contains only the V1 baseline (no migration stages needed yet).
/// When adding V2, add a new VersionedSchema enum and a lightweight stage here.
///
/// Example for future V2:
/// ```
/// public enum DiverSchemaV2: VersionedSchema {
///     public static var versionIdentifier = Schema.Version(2, 0, 0)
///     public static var models: [any PersistentModel.Type] {
///         // Updated model list
///     }
/// }
///
/// // In DiverMigrationPlan:
/// static var schemas: [..., DiverSchemaV2.self]
/// static var stages: [migrateV1toV2]
/// static let migrateV1toV2 = MigrationStage.lightweight(
///     fromVersion: DiverSchemaV1.self, toVersion: DiverSchemaV2.self
/// )
/// ```
public enum DiverMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [DiverSchemaV1.self]
    }
    
    public static var stages: [MigrationStage] {
        [] // No migrations yet — V1 is the current baseline
    }
}
