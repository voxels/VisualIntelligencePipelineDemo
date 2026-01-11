//
//  JobProgress.swift
//  Diver
//
//  Job processing progress tracking
//

import Foundation
import SwiftData

/// Job processing status
enum JobStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

/// Log entry from job processing
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: String
    let message: String
    
    init(id: UUID = UUID(), timestamp: Date = Date(), level: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
    
    init(from event: SSEEvent) {
        self.id = UUID()
        self.level = event.level
        self.message = event.message
        
        // Parse ISO timestamp
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.date(from: event.timestamp) ?? Date()
    }
    
    var emoji: String {
        switch level.lowercased() {
        case "error": return "❌"
        case "warning": return "⚠️"
        case "info": return "ℹ️"
        case "debug": return "🔍"
        default: return "📝"
        }
    }
}

/// Job progress tracker
@Observable
class JobProgress {
    var jobId: UUID
    var status: JobStatus = .pending
    var logs: [LogEntry] = []
    var startedAt: Date?
    var completedAt: Date?
    var isStreaming: Bool = false
    
    init(jobId: UUID) {
        self.jobId = jobId
    }
    
    func addLog(_ event: SSEEvent) {
        let entry = LogEntry(from: event)
        logs.append(entry)
        
        // Update status based on log messages
        if event.message.contains("complete") || event.message.contains("✅") {
            status = .completed
            completedAt = Date()
        } else if event.message.contains("error") || event.message.contains("❌") {
            status = .failed
            completedAt = Date()
        } else if status == .pending {
            status = .processing
            startedAt = Date()
        }
    }
    
    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "—" }
        
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
