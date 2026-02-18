import XCTest
import SwiftData
import DiverShared
@testable import DiverKit

// MARK: - QueueProgressEvent Tests
//
// Tests for:
//   1. QueueProgressEvent enum computed properties (progress, isProcessing)
//   2. AsyncStream emission from MetadataPipelineService
//   3. Cancellation emits .cancelled event

// MARK: - 1. QueueProgressEvent Value Tests

final class QueueProgressEventTests: XCTestCase {
    
    func testStartedProgress() {
        let event = QueueProgressEvent.started(totalCount: 10)
        XCTAssertEqual(event.progress, 0)
        XCTAssertTrue(event.isProcessing)
    }
    
    func testProcessingItemProgress() {
        let event = QueueProgressEvent.processingItem(
            completedCount: 3,
            totalCount: 10,
            itemTitle: "Test",
            statusMessage: "Analyzing..."
        )
        XCTAssertEqual(event.progress, 0.3)
        XCTAssertTrue(event.isProcessing)
    }
    
    func testItemCompletedProgress() {
        let event = QueueProgressEvent.itemCompleted(completedCount: 5, totalCount: 10)
        XCTAssertEqual(event.progress, 0.5)
        XCTAssertTrue(event.isProcessing)
    }
    
    func testCompletedProgress() {
        let event = QueueProgressEvent.completed(totalCount: 10)
        XCTAssertEqual(event.progress, 1.0)
        XCTAssertFalse(event.isProcessing)
    }
    
    func testCancelledProgress() {
        let event = QueueProgressEvent.cancelled
        XCTAssertEqual(event.progress, 0)
        XCTAssertFalse(event.isProcessing)
    }
    
    func testZeroTotalProgressDoesNotDivideByZero() {
        let event = QueueProgressEvent.processingItem(
            completedCount: 0,
            totalCount: 0,
            itemTitle: nil,
            statusMessage: nil
        )
        XCTAssertEqual(event.progress, 0)
    }
}

// MARK: - 2. AsyncStream Emission Tests

@MainActor
final class QueueProgressStreamTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var queueStore: DiverQueueStore!
    var pipelineService: MetadataPipelineService!
    var tempURL: URL!
    
    override func setUp() async throws {
        let manager = makeTestDataManager()
        modelContainer = manager.container
        modelContext = manager.mainContext
        
        tempURL = try makeTemporaryDirectory()
        queueStore = try DiverQueueStore(directoryURL: tempURL)
        
        pipelineService = MetadataPipelineService(
            queueStore: queueStore,
            modelContainer: modelContainer,
            mainContext: modelContext
        )
    }
    
    override func tearDown() async throws {
        pipelineService.cancelProcessing()
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    /// Verifies that cancelling processing emits a .cancelled event on the progress stream.
    func testCancelProcessingEmitsCancelledEvent() async throws {
        // Given: Subscribe to the progress stream
        var receivedEvents: [QueueProgressEvent] = []
        
        let expectation = XCTestExpectation(description: "Receive cancelled event")
        
        let task = Task {
            for await event in pipelineService.progressStream {
                receivedEvents.append(event)
                if case .cancelled = event {
                    expectation.fulfill()
                    break
                }
            }
        }
        
        // Brief pause to ensure the stream subscription is active
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // When: Simulate active processing then cancel
        pipelineService.queueTotalCount = 5
        pipelineService.isProcessingQueue = true
        pipelineService.cancelProcessing()
        
        // Then: Should receive the cancelled event
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertFalse(receivedEvents.isEmpty, "Should have received at least one event")
        
        if case .cancelled = receivedEvents.last {
            // Expected
        } else {
            XCTFail("Last event should be .cancelled, got: \(String(describing: receivedEvents.last))")
        }
        
        task.cancel()
    }
    
    /// Verifies that the QueueProgressEvent.progress property correctly calculates fractions.
    func testProgressFractionCalculation() {
        // 0/10 = 0%
        let start = QueueProgressEvent.started(totalCount: 10)
        XCTAssertEqual(start.progress, 0.0, accuracy: 0.001)
        
        // 3/10 = 30%
        let mid = QueueProgressEvent.itemCompleted(completedCount: 3, totalCount: 10)
        XCTAssertEqual(mid.progress, 0.3, accuracy: 0.001)
        
        // 10/10 = 100%
        let done = QueueProgressEvent.itemCompleted(completedCount: 10, totalCount: 10)
        XCTAssertEqual(done.progress, 1.0, accuracy: 0.001)
        
        // Completed always 100%
        let completed = QueueProgressEvent.completed(totalCount: 10)
        XCTAssertEqual(completed.progress, 1.0, accuracy: 0.001)
    }
    
    /// Verifies that multiple cancel calls don't crash the stream.
    func testMultipleCancelCallsAreSafe() async throws {
        var eventCount = 0
        
        let expectation = XCTestExpectation(description: "Receive at least one cancelled event")
        
        let task = Task {
            for await event in pipelineService.progressStream {
                eventCount += 1
                if case .cancelled = event {
                    expectation.fulfill()
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Cancel multiple times — should not crash
        pipelineService.cancelProcessing()
        pipelineService.cancelProcessing()
        pipelineService.cancelProcessing()
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // At least the first cancel should have emitted
        XCTAssertGreaterThanOrEqual(eventCount, 1)
        
        task.cancel()
    }
    
    /// Verifies that the isProcessing property correctly reflects active states.
    func testIsProcessingForAllEventTypes() {
        let activeEvents: [QueueProgressEvent] = [
            .started(totalCount: 5),
            .processingItem(completedCount: 1, totalCount: 5, itemTitle: "test", statusMessage: nil),
            .itemCompleted(completedCount: 2, totalCount: 5)
        ]
        
        let inactiveEvents: [QueueProgressEvent] = [
            .completed(totalCount: 5),
            .cancelled
        ]
        
        for event in activeEvents {
            XCTAssertTrue(event.isProcessing, "Expected isProcessing=true for \(event)")
        }
        
        for event in inactiveEvents {
            XCTAssertFalse(event.isProcessing, "Expected isProcessing=false for \(event)")
        }
    }
}
