import Foundation

/// Manages an internal queue of incoming processing requests on the Edge Daemon.
/// Ensures that heavy VLM and LLM inference tasks run sequentially and do not overwhelm 
/// the MLX processor by trying to evaluate multiple models simultaneously.
public actor EdgeQueueManager {
    public static let shared = EdgeQueueManager()
    
    private var isProcessing = false
    private var queue: [() async throws -> Data] = []
    
    public init() {}
    
    /// Enqueues a task that returns a serialized Data payload.
    /// Resumes the caller with the result once the task reaches the front of the queue and completes.
    public func enqueue(_ operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let item: () async throws -> Data = {
                do {
                    let result = try await operation()
                    continuation.resume(returning: result)
                    return result
                } catch {
                    continuation.resume(throwing: error)
                    throw error
                }
            }
            queue.append(item)
            
            Task {
                await processNextIfNeeded()
            }
        }
    }
    
    private func processNextIfNeeded() async {
        guard !isProcessing, !queue.isEmpty else { return }
        
        isProcessing = true
        let operation = queue.removeFirst()
        
        do {
            _ = try await operation()
        } catch {
            print("⚠️ [EdgeQueueManager] Operation failed: \(error)")
        }
        
        isProcessing = false
        await processNextIfNeeded()
    }
}
