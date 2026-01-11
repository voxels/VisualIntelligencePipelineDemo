import Foundation
import SwiftData
import DiverShared

public struct PipelineImportService {
    @MainActor
    public static func importExamples(modelContext: ModelContext) async throws {
        // For now, allow multiple imports for testing until we are sure it's working perfectly.
        // We can re-enable this later or use it to skip redundant work.
        DiverLogger.pipeline.info("Starting pipeline example import...")

        // 2. Find the fixture file
        // Try DiverBundle.module first for reliability, then Bundle.main
        var url = DiverBundle.module.url(forResource: "pipeline_logs", withExtension: "json")
        
        if url == nil {
            url = Bundle.main.url(forResource: "pipeline_logs", withExtension: "json")
        }
        
        if url == nil {
            // Exhaustive search through all bundles in case it's in a framework bundle
            for bundle in Bundle.allBundles {
                if let found = bundle.url(forResource: "pipeline_logs", withExtension: "json") {
                    url = found
                    DiverLogger.pipeline.debug("Found pipeline_logs.json in bundle: \(bundle.bundlePath)")
                    break
                }
            }
        }

        if url == nil {
            for bundle in Bundle.allFrameworks {
                if let found = bundle.url(forResource: "pipeline_logs", withExtension: "json") {
                    url = found
                    DiverLogger.pipeline.debug("Found pipeline_logs.json in framework: \(bundle.bundlePath)")
                    break
                }
            }
        }

        guard let finalURL = url else {
            DiverLogger.pipeline.error("❌ Failed to find pipeline_logs.json in any bundle.")
            throw NSError(domain: "PipelineImport", code: 404, userInfo: [NSLocalizedDescriptionKey: "Example data file (pipeline_logs.json) not found in bundle."])
        }

        let data = try Data(contentsOf: finalURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        
        let root = try decoder.decode(PipelineRoot.self, from: data)
        
        for log in root.logs {
            let logId = log.jobUuid
            
            // Try to find existing item first
            let fetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.id == logId }
            )
            let existingItem = try? modelContext.fetch(fetch).first
            
            let processedItem: ProcessedItem
            if let existing = existingItem {
                DiverLogger.pipeline.debug("Updating existing item from import: \(logId)")
                processedItem = existing
                processedItem.status = .ready // Ensure it's ready
                processedItem.updatedAt = Date() // Force to top
            } else {
                DiverLogger.pipeline.debug("Creating new item from import: \(logId)")
                processedItem = ProcessedItem(
                    id: logId,
                    inputId: log.inputId,
                    status: .ready,
                    source: "pipeline_import",
                    updatedAt: Date()
                )
                modelContext.insert(processedItem)
            }
            
            for entry in log.entries {
                if let payload = entry.payload.value as? [String: Any] {
                    // Handle media_analysis
                    if payload["message_type"] as? String == "media_analysis",
                       let mediaData = payload["media_data"] as? [String: Any] {
                        
                        let title = mediaData["title"] as? String
                        if let title, !title.isEmpty {
                            processedItem.title = title
                        } else if processedItem.title == nil || processedItem.title?.isEmpty == true {
                             processedItem.title = mediaData["filename"] as? String
                        }
                        
                        if let summary = mediaData["description"] as? String {
                            processedItem.summary = summary
                        }
                        
                        if let transcription = mediaData["transcription"] as? String {
                            processedItem.transcription = transcription
                        }
                        
                        processedItem.url = mediaData["url"] as? String
                        processedItem.mediaType = mediaData["media_type"] as? String
                        processedItem.fileSize = mediaData["file_size"] as? Int
                        processedItem.filename = mediaData["filename"] as? String
                        
                        if let themes = mediaData["themes"] as? [String] {
                            processedItem.themes = themes
                        }
                    }
                    

                }
            }
        }
        
        try modelContext.save()
        DiverLogger.pipeline.info("✅ Saved imported items to SwiftData")
        
        // Ensure the pipeline processes the new inputs immediately
        let queueDirectory = AppGroupContainer.queueDirectoryURL()!
        let queueStore = try! DiverQueueStore(directoryURL: queueDirectory)
        let pipelineService = MetadataPipelineService(queueStore: queueStore, modelContext: modelContext)
        try await pipelineService.refreshProcessedItems()
        
        UserDefaults.standard.set(true, forKey: "DiverPipelineImported")
        DiverLogger.pipeline.info("✅ Successfully imported pipeline examples")
    }
}

// MARK: - Decoding Helpers

private struct PipelineRoot: Codable {
    let logs: [PipelineLog]
}

private struct PipelineLog: Codable {
    let jobUuid: String
    let inputId: String
    let entries: [PipelineEntry]
    
    enum CodingKeys: String, CodingKey {
        case jobUuid = "job_uuid"
        case inputId = "input_id"
        case entries
    }
}

private struct PipelineEntry: Codable {
    let payload: AnyJSON
}

private struct AnyJSON: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) { value = x }
        else if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(Double.self) { value = x }
        else if let x = try? container.decode(Bool.self) { value = x }
        else if let x = try? container.decode([String: AnyJSON].self) { value = x.mapValues { $0.value } }
        else if let x = try? container.decode([AnyJSON].self) { value = x.map { $0.value } }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        // Not needed for import
    }
}
