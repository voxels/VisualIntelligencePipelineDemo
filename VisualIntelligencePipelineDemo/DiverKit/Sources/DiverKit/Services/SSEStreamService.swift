//
//  SSEStreamService.swift
//  Diver
//
//  Server-Sent Events streaming service using LaunchDarkly EventSource
//  https://github.com/launchdarkly/swift-eventsource
//

import Foundation
import Combine
import LDSwiftEventSource

/// SSE Stream Service - Uses LaunchDarkly EventSource
/// Safety: @unchecked Sendable — mutable `eventSource` and `continuation` are accessed
/// from a single-stream lifecycle (one stream active at a time). EventHandler callbacks
/// are serialized by the EventSource library. However, stopStream() could technically
/// race with onMessage() — consider adding NSLock if concurrent stop/event scenarios arise.
final class SSEStreamService: @unchecked Sendable {
    private var eventSource: EventSource?
    private var continuation: AsyncStream<SSEEvent>.Continuation?
    
    init() {
        print("🔧 SSEStreamService initialized")
    }
    
    deinit {
        print("🗑️ SSEStreamService deinitialized")
        stopStream()
    }
    
    /// Stream SSE events from server using EventSource library
    func streamJobLogs(jobId: UUID, baseURL: String, token: String) -> AsyncStream<SSEEvent> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            self.continuation = continuation
            
            // Convert UUID to lowercase to match backend Redis channel format
            let jobUUID = jobId.uuidString.lowercased()
            let urlString = "\(baseURL)/jobs/\(jobUUID)/stream"
            print("📡 Connecting to SSE for job: \(jobUUID)")
            
            guard let url = URL(string: urlString) else {
                print("❌ Invalid SSE URL")
                continuation.finish()
                return
            }
            
            // Configure EventSource (no auth - SSE endpoint is public)
            var config = EventSource.Config(handler: self, url: url)
            config.headers = [
                "Accept": "text/event-stream"
            ]
            config.reconnectTime = 5.0
            config.maxReconnectTime = 30.0
            
            print("🔑 Using token: \(token.prefix(20))...")
            
            // Create and start EventSource
            let eventSource = EventSource(config: config)
            self.eventSource = eventSource
            eventSource.start()
            
            print("✅ EventSource started for job \(jobId)")
            
            continuation.onTermination = { [weak self] _ in
                self?.stopStream()
            }
        }
    }
    
    func stopStream() {
        print("🛑 Stopping EventSource")
        eventSource?.stop()
        eventSource = nil
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - EventHandler
extension SSEStreamService: EventHandler {
    func onOpened() {
        print("✅ SSE connection opened")
    }
    
    func onClosed() {
        print("🔌 SSE connection closed")
        continuation?.finish()
    }
    
    func onMessage(eventType: String, messageEvent: MessageEvent) {
        print("📥 Event: '\(eventType)' Data: \(messageEvent.data)")
        
        guard let data = messageEvent.data.data(using: .utf8) else {
            print("   ❌ Failed to convert data to UTF8")
            return
        }
        
        do {
            let sseEvent = try JSONDecoder().decode(SSEEvent.self, from: data)
            print("   ✅ Decoded SSEEvent: \(sseEvent.message)")
            continuation?.yield(sseEvent)
        } catch {
            print("   ❌ Failed to decode SSEEvent: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("      Missing key: \(key.stringValue) - \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("      Type mismatch for type: \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("      Value not found for type: \(type) - \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("      Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("      Unknown decoding error")
                }
            }
        }
    }
    
    func onComment(comment: String) {
        print("💬 Comment: \(comment)")
    }
    
    func onError(error: Error) {
        print("❌ SSE error: \(error)")
        continuation?.finish()
    }
}
