import XCTest
import DiverKit
import DiverShared

@MainActor
final class VisualIntelligenceViewModelTests: XCTestCase {
    
    func testInitialState() {
        let vm = VisualIntelligenceViewModel()
        
        // Results should start empty
        XCTAssertTrue(vm.results.isEmpty)
        
        // Default peel amount 0
        XCTAssertEqual(vm.peelAmount, 0.0)
        
        // No capture time yet
        XCTAssertNil(vm.lastCaptureTime)
        
        // Not recording by default (CameraManager default)
        XCTAssertFalse(vm.cameraManager.isRecording)
    }
    
    func testStartStopRecording() {
        let vm = VisualIntelligenceViewModel()
        
        vm.startRecording()
        XCTAssertTrue(vm.cameraManager.isRecording)
        
        vm.stopRecording()
        XCTAssertFalse(vm.cameraManager.isRecording)
    }
    
    func testUpdatePeelAmount() {
        let vm = VisualIntelligenceViewModel()
        
        vm.updatePeelAmount(0.5)
        XCTAssertEqual(vm.peelAmount, 0.5)
        
        vm.updatePeelAmount(1.0)
        XCTAssertEqual(vm.peelAmount, 1.0)
    }
    
    func testHandleCaptureWithQR() async throws {
        // Given: A VM with a real generator in a temp directory
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        let store = try DiverQueueStore(directoryURL: tempURL)
        let secret = Data([0x01, 0x02, 0x03])
        let generator = DiverLinkGenerator(store: store, secret: secret)
        
        let vm = VisualIntelligenceViewModel(linkGenerator: generator)
        
        // When: We simulate a QR result and trigger capture
        let testURL = URL(string: "https://example.com")!
        let result = IntelligenceResult.qr(testURL)
        
        vm.setupCameraBridge() // Ensure callbacks are hooked up first
        vm.handleCapture(result: result)
        
        // Then: Wait a bit for the async Task and check the store
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s
        
        let pending = try store.pendingEntries()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.item.descriptor.url, testURL.absoluteString)
        
        // Cleanup
        try FileManager.default.removeItem(at: tempURL)
    }
    func testResetClearsState() {
        let vm = VisualIntelligenceViewModel()
        
        // Set some state
        // Note: capturedImage and results are MainActor isolated or Published, so setting them is fine here
        vm.capturedImage = UIImage()
        vm.results = [.qr(URL(string: "https://example.com")!)]
        vm.sessionImages = [UIImage()]
        vm.isSaving = true
        vm.showingSaveError = true
        vm.saveErrorMessage = "Error"
        
        // Trigger reset
        vm.reset()
        
        // Assert state is cleared
        XCTAssertNil(vm.capturedImage)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertTrue(vm.sessionImages.isEmpty)
        XCTAssertFalse(vm.isSaving)
        XCTAssertFalse(vm.showingSaveError)
        XCTAssertNil(vm.saveErrorMessage)
    }
}
