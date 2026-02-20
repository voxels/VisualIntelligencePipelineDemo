//
//  PersistenceActor.swift
//  DiverKit
//
//  A @ModelActor for background SwiftData operations.
//  Replaces manual ModelContext(container) + Task.detached patterns
//  with proper actor-isolated SwiftData access.
//
//  Usage:
//    let actor = PersistenceActor(modelContainer: container)
//    await actor.analyzeSession(sessionID: "...")
//    let data = try await actor.fetchScoreHistory(productID: "...")
//

import Foundation
import SwiftData
import DiverShared

/// Actor-isolated background SwiftData operations.
/// The @ModelActor macro auto-generates a ModelContainer property and
/// creates an isolated ModelContext for all operations on this actor.
@ModelActor
public actor PersistenceActor {
    
    // MARK: - Session Analysis
    
    /// Generates and saves a session summary on this actor's isolated context.
    public func analyzeSession(sessionID: String) async {
        let localPipeline = LocalPipelineService(modelContext: modelContext)
        await localPipeline.generateAndSaveSessionSummary(sessionID: sessionID)
        print("✅ PersistenceActor: Analyzed session \(sessionID)")
    }
    
    // MARK: - Ethical Policy Settings
    
    /// Fetches or creates the singleton EthicalPolicySettings and returns a Sendable `EthicalPolicy`.
    /// Safe to call from any isolation context — `EthicalPolicy` conforms to `Sendable`.
    public func fetchOrCreatePolicySettings() -> EthicalPolicy {
        let settings = EthicalPolicySettings.current(in: modelContext)
        return EthicalPolicy(
            carbonThreshold: settings.carbonThreshold,
            preferredCertifications: settings.certifications,
            platformRanking: settings.platformRanking,
            excludeLaborViolations: settings.excludeLaborViolations
        )
    }
    
    // MARK: - Score History
    
    /// Fetches ScoreSnapshot records and maps to Sendable chart-ready structs.
    public func fetchScoreHistory(productID: String, limit: Int = 50) throws -> [ScoreSnapshotData] {
        var descriptor = FetchDescriptor<ScoreSnapshot>(
            predicate: #Predicate { $0.productID == productID },
            sortBy: [SortDescriptor(\ScoreSnapshot.recordedAt)]
        )
        descriptor.fetchLimit = limit
        
        let snapshots = try modelContext.fetch(descriptor)
        
        return snapshots.flatMap { snapshot in
            snapshot.strategyScores.map { entry in
                ScoreSnapshotData(
                    date: snapshot.recordedAt,
                    score: Double(entry.score),
                    strategyID: entry.strategyID
                )
            }
        }
    }
}
