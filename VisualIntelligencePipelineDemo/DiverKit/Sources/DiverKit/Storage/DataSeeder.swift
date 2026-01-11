import Foundation
import SwiftData
import DiverShared

@MainActor
public struct DataSeeder {
    
    // Codable structures for parsing pipeline_logs.json
    // We only decode enough to extract the data we need
    private struct Root: Decodable {
        let logs: [LogEntry]
    }
    
    private struct LogEntry: Decodable {
        let job_uuid: String
        let entries: [Entry]
    }
    
    private struct Entry: Decodable {
        let payload: Payload
    }
    
    // Dynamic decoding for payload since it varies
    private enum Payload: Decodable {
        case mediaAnalysis(MediaAnalysisPayload)
        case music(MusicPayload)
        case book(BookPayload)
        case unknown
        
        private enum CodingKeys: String, CodingKey {
            case message_type, type
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            if let msgType = try? container.decode(String.self, forKey: .message_type), msgType == "media_analysis" {
                let payload = try MediaAnalysisPayload(from: decoder)
                self = .mediaAnalysis(payload)
                return
            }
            
            if let type = try? container.decode(String.self, forKey: .type) {
                if type == "music" {
                    let payload = try MusicPayload(from: decoder)
                    self = .music(payload)
                    return
                }
                if type == "book" {
                    let payload = try BookPayload(from: decoder)
                    self = .book(payload)
                    return
                }
            }
            
            self = .unknown
        }
    }
    
    private struct MediaAnalysisPayload: Codable {
        let media_id: String
        let media_data: MediaData
    }
    
    private struct MediaData: Codable {
        let description: String?
        let title: String?
        let detected_objects: [String]?
        let transcription: String?
        let url: String?
        let themes: [String]?
        let media_type: String?
        let file_size: Int?
        let filename: String?
    }
    
    private struct MusicPayload: Codable {
        let created_references: [ReferenceMetadata]?
    }
    
    private struct BookPayload: Codable {
        // Book payload usually doesn't have created_references based on the log, but let's check
        // The log example shows 'created_references' in the 'music' payload.
        // Let's assume consistent structure if books are created.
        // Actually log 2 (books) doesn't show created_references. It shows candidates.
        // So we might only get references if the pipeline successfully matched them.
        // For this seeder, we'll focus on what's available.
        let created_references: [ReferenceMetadata]?
    }
    
    private struct ReferenceMetadata: Codable {
        let entity_type: String
        let name: String
        let id: String
        let reference_metadata: ReferenceDetails?
    }
    
    private struct ReferenceDetails: Codable {
        let title: String?
        let artists: [String]?
        let album_type: String?
        let spotify_id: String?
        let release_date: String?
        let total_tracks: Int?
        let external_urls: ExternalURLs?
    }
    
    private struct ExternalURLs: Codable {
        let spotify: String?
    }

    /// Seeds the database with sample data if it is empty
    public static func seed(context: ModelContext) throws {
        // 1. Check if empty
        let count = try context.fetchCount(FetchDescriptor<ProcessedItem>())
        guard count == 0 else {
            print("Database not empty. Seeding skipped.")
            return
        }
        
        print("Seeding database with sample data...")
        
        // 2. Load JSON
        guard let url = Bundle.module.url(forResource: "pipeline_logs", withExtension: "json") else {
            print("Error: Could not find pipeline_logs.json in bundle.")
            return
        }
        
        let data = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(Root.self, from: data)
        
        // 3. Map and Insert
        for log in root.logs {
            var inputItem: ProcessedItem? = nil
            for entry in log.entries {
                switch entry.payload {
                case .mediaAnalysis(let p):
                    // Create ProcessedItem with smart title extraction
                    let title: String = {
                        // Try title first
                        if let t = p.media_data.title, !t.isEmpty {
                            return t
                        }
                        // Try first sentence of transcription
                        if let trans = p.media_data.transcription, !trans.isEmpty {
                            let firstSentence = trans.components(separatedBy: ".")
                                .first?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let sentence = firstSentence, !sentence.isEmpty {
                                return sentence.count > 100 ? String(sentence.prefix(100)) + "..." : sentence
                            }
                        }
                        // Try first sentence of description
                        if let desc = p.media_data.description, !desc.isEmpty {
                            let firstSentence = desc.components(separatedBy: ".")
                                .first?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let sentence = firstSentence, !sentence.isEmpty {
                                return sentence.count > 100 ? String(sentence.prefix(100)) + "..." : sentence
                            }
                        }
                        return "Untitled"
                    }()
                    
                    let item = ProcessedItem(
                        id: p.media_id,
                        url: p.media_data.url,
                        title: title,
                        summary: p.media_data.description,
                        tags: p.media_data.detected_objects ?? [],
                        status: .ready,
                        transcription: p.media_data.transcription,
                        themes: p.media_data.themes ?? [],
                        mediaType: p.media_data.media_type,
                        fileSize: p.media_data.file_size,
                        filename: p.media_data.filename
                    )
                    context.insert(item)
                    inputItem = item
                    
                case .music(let p):
                    if let ref = p.created_references?.first {
                         let item = ProcessedItem(
                             id: ref.id,
                             url: ref.reference_metadata?.external_urls?.spotify,
                             title: ref.reference_metadata?.title ?? ref.name,
                             summary: "Music by \(ref.reference_metadata?.artists?.joined(separator: ", ") ?? "Unknown")",
                             tags: ["Music", ref.entity_type],
                             status: .ready,
                             mediaType: "audio"
                         )
                         context.insert(item)
                         inputItem = item
                    }
                    
                case .book(let p):
                    if let ref = p.created_references?.first {
                         let item = ProcessedItem(
                             id: ref.id,
                             url: nil,
                             title: ref.reference_metadata?.title ?? ref.name,
                             summary: "Book: \(ref.name)",
                             tags: ["Book", ref.entity_type],
                             status: .ready,
                             mediaType: "text"
                         )
                         context.insert(item)
                         inputItem = item
                    }
                case .unknown:
                    continue
                }
            }
            
            if let item = inputItem {
                // Ensure date is updated
                item.updatedAt = Date()
            }
        }
        
        try context.save()
        print("Database seeded successfully with \(root.logs.count) logs.")
    }
}
