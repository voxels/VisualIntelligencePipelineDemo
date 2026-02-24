//
//  BackgroundSummaryService.swift
//  DiverKit
//
//  Monitors for an active Edge Connection and silently upgrades 
//  `[Model: SystemLanguageModel-iOS26]` summaries to `[Model: Edge-MLX-CLaRa]` ones.
//

import Distributed
import DiverShared
import Foundation
import SwiftData

/// Non-blocking actor that silently upgrades local LLM summaries using the Edge node.
@ModelActor
public actor BackgroundSummaryService {

  private var currentTask: Task<Void, Never>?

  /// Starts the background upgrade process if an Edge node is available and we aren't already running.
  public func startUpgradesIfNeeded(router: PipelineEdgeRouter, system: VisualIntelligenceActorSystem) {
    guard currentTask == nil else { return }

    currentTask = Task(priority: .background) {
      let decision = await router.shouldOffload(task: .vlmInference)
      print("🔄 [BackgroundSummaryService] Routing decision: \(decision)")
      guard case .edge(let node, _) = decision else {
        await self.clearTask()
        return
      }

      print(
        "🔄 [BackgroundSummaryService] Edge node '\(node.deviceName)' detected. Starting silent summary upgrades..."
      )

      await self.performUpgrades(nodeName: node.deviceName, system: system)
      await self.clearTask()
    }
  }

  private func performUpgrades(nodeName: String, system: VisualIntelligenceActorSystem) async {
    // @ModelActor provides `modelContext` natively
    self.modelContext.autosaveEnabled = false

    do {
      try await self.upgradeProcessedItems(nodeName: nodeName, system: system)
      guard !Task.isCancelled else { return }
      try await self.upgradeSessions(nodeName: nodeName, system: system)
    } catch {
      if Task.isCancelled {
        print("🛑 [BackgroundSummaryService] Upgrade cycle cancelled.")
      } else {
        print("❌ [BackgroundSummaryService] Upgrade cycle failed: \(error)")
      }
    }
  }

  public func cancelUpgrades() {
    currentTask?.cancel()
    currentTask = nil
    print("🛑 [BackgroundSummaryService] Cancelling background upgrades...")
  }

  private func clearTask() {
    self.currentTask = nil
  }

  private func upgradeProcessedItems(nodeName: String, system: VisualIntelligenceActorSystem)
    async throws
  {
    // Find ProcessedItems with the old model tag or heuristic fallback
    // We use predicate string matching so SQLite filters it natively
    var descriptor = FetchDescriptor<ProcessedItem>(
      predicate: #Predicate { item in
        if let summary = item.summary {
          // Upgrade any item NOT already summarized by CLaRa
          return summary.contains("[Model:") && !summary.contains("[Model: Edge-CLaRa-7B]")
        } else {
          return false
        }
      },
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 5

    let itemsToUpgrade = try modelContext.fetch(descriptor)

    guard !itemsToUpgrade.isEmpty else { return }

    let identity = EdgeActorID(id: "EdgeContext", nodeName: nodeName)
    let edgeActor = try EdgeContextActor.resolve(id: identity, using: system)

    for item in itemsToUpgrade {
      guard let oldSummary = item.summary, !Task.isCancelled else { continue }
      print("🧠 [BackgroundSummaryService] Upgrading ProcessedItem summary for \(item.id)...")

      do {
        var contextParts: [String] = []
        if let t = item.title { contextParts.append("Title: \(t)") }
        if let o = item.transcription { contextParts.append("OCR: \(o.prefix(800))") }
        if !item.tags.isEmpty { contextParts.append("Tags: \(item.tags.joined(separator: ", "))") }
        if !item.categories.isEmpty { contextParts.append("Categories: \(item.categories.joined(separator: ", "))") }
        if let mt = item.mediaType { contextParts.append("Media Type: \(mt)") }
        if let p = item.placeContext {
          if let name = p.name { contextParts.append("Venue: \(name)") }
          if let addr = p.address { contextParts.append("Address: \(addr)") }
        }
        if let loc = item.location { contextParts.append("Location: \(loc)") }
        if let webCtx = item.webContext {
          if let site = webCtx.siteName { contextParts.append("Web Site: \(site)") }
          if let text = webCtx.textContent { contextParts.append("Web Content: \(String(text.prefix(300)))") }
        }
        if let vlm = item.fastVLMAnalysis {
          if let ctx = vlm.contextSummary { contextParts.append("Visual Analysis: \(String(ctx.prefix(500)))") }
        }
        if !item.questions.isEmpty { contextParts.append("Questions: \(item.questions.joined(separator: "; "))") }
        if let score = item.aestheticsScore, score > 0 { contextParts.append("Quality Score: \(String(format: "%.0f%%", score * 100))") }
        if let product = item.productMetadata { contextParts.append("Product: \(product)") }

        let textToSummarize: String
        if !contextParts.isEmpty {
          textToSummarize = contextParts.joined(separator: "\n")
        } else {
          textToSummarize =
            "Rewrite the following into a very concise 1-sentence activity description: \(oldSummary)"
        }

        var attempt = 1
        var success = false
        while attempt <= 3 && !success && !Task.isCancelled {
          do {
            let newSummary = try await edgeActor.summarize(text: textToSummarize, imageData: item.rawPayload)
            if !Task.isCancelled {
              // EdgeContextActor may badge CLaRa summaries itself — don't double-badge
              item.summary = newSummary.contains("[Model:") ? newSummary : "\(newSummary) [Model: Edge-FastVLM]"
              item.updatedAt = Date()
              item.processingLog.append(
                "\(Date().formatted()): Summary silently upgraded by Edge Context Actor")
              try modelContext.save()
              print(
                "🌟 [BackgroundSummaryService] Successfully upgraded ProcessedItem \(item.id)")
              success = true
              // Pacing to avoid overwhelming the edge processor
              try await Task.sleep(for: .seconds(2))
            }
          } catch {
            print(
              "⚠️ [BackgroundSummaryService] Attempt \(attempt) failed for item \(item.id): \(error)"
            )
            attempt += 1
            if attempt <= 3 {
              // Exponential-ish backoff
              try await Task.sleep(for: .seconds(Double(attempt * 2)))
            }
          }
        }
      } catch {
        print("⚠️ [BackgroundSummaryService] Outer fetch failed for item \(item.id): \(error)")
      }
    }
  }

  private func upgradeSessions(nodeName: String, system: VisualIntelligenceActorSystem) async throws
  {
    var sessionDesc = FetchDescriptor<SessionMetadata>(
      predicate: #Predicate { session in
        if let summary = session.summary {
          // Upgrade any session NOT already summarized by CLaRa
          return summary.contains("[Model:") && !summary.contains("[Model: Edge-CLaRa-7B]")
        } else {
          return false
        }
      },
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    sessionDesc.fetchLimit = 5

    let sessionsToUpgrade = try modelContext.fetch(sessionDesc)

    guard !sessionsToUpgrade.isEmpty else { return }

    let identity = EdgeActorID(id: "EdgeContext", nodeName: nodeName)
    let edgeActor = try EdgeContextActor.resolve(id: identity, using: system)

    for session in sessionsToUpgrade {
      guard let oldSummary = session.summary, !Task.isCancelled else { continue }
      print("🧠 [BackgroundSummaryService] Upgrading Session summary for \(session.sessionID)...")

      do {
        let sid = session.sessionID
        let itemDesc = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sid })
        let items = try modelContext.fetch(itemDesc)

        let contextParts = items.compactMap { $0.title }.joined(separator: ", ")
        let textToSummarize: String
        if !contextParts.isEmpty {
          textToSummarize =
            "Session at \(session.locationName ?? "Unknown") containing items: \(contextParts)"
        } else {
          textToSummarize = "Summarize this session concisely: \(oldSummary)"
        }
        
        // Select best representative image from session items
        let sortedByScore: [ProcessedItem] = items.sorted { ($0.aestheticsScore ?? 0) > ($1.aestheticsScore ?? 0) }
        let bestImagePayload: Data? = sortedByScore.first(where: { $0.rawPayload != nil })?.rawPayload

        var attempt = 1
        var success = false
        while attempt <= 3 && !success && !Task.isCancelled {
          do {
            let newSummary = try await edgeActor.summarize(text: textToSummarize, imageData: bestImagePayload)
            if !Task.isCancelled {
              // EdgeContextActor may badge CLaRa summaries itself — don't double-badge
              session.summary = newSummary.contains("[Model:") ? newSummary : "\(newSummary) [Model: Edge-FastVLM]"
              session.updatedAt = Date()
              try modelContext.save()
              print(
                "🌟 [BackgroundSummaryService] Successfully upgraded Session \(session.sessionID)")
              success = true
              // Pacing to avoid overwhelming the edge processor
              try await Task.sleep(for: .seconds(2))
            }
          } catch {
            print(
              "⚠️ [BackgroundSummaryService] Attempt \(attempt) failed for session \(session.sessionID): \(error)"
            )
            attempt += 1
            if attempt <= 3 {
              try await Task.sleep(for: .seconds(Double(attempt * 2)))
            }
          }
        }
      } catch {
        print(
          "⚠️ [BackgroundSummaryService] Failed to upgrade session \(session.sessionID): \(error)")
      }
    }
  }
}
