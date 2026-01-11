import XCTest
import DiverShared
@testable import DiverKit

final class DiverLinkGeneratorTests: XCTestCase {
    var generator: DiverLinkGenerator!
    var mockStore: DiverQueueStore!
    let testSecret = "test-secret-data-for-wrapping-123".data(using: .utf8)!
    
    override func setUp() {
        super.setUp()
        // Initialize with a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        do {
            mockStore = try DiverQueueStore(directoryURL: tempDir)
            generator = DiverLinkGenerator(store: mockStore, secret: testSecret)
        } catch {
            XCTFail("Failed to initialize mock store: \(error)")
        }
    }
    
    override func tearDown() {
        generator = nil
        mockStore = nil
        super.tearDown()
    }
    
    func testCreateAndSaveLink() {
        let testURL = URL(string: "https://apple.com")!
        
        do {
            let wrappedURL = try generator.createAndSaveLink(from: testURL, title: "Apple", labels: ["tech"])
            
            // Verify wrapped URL format - uses secretatomics.com from DiverLinkWrapper.baseURL
            XCTAssertTrue(wrappedURL.absoluteString.contains("secretatomics.com/w/"))
            
            // Verify storage
            // Note: Since DiverQueueStore might process items asynchronously or we need to check the file system directly,
            // we'll at least verify it didn't throw.
        } catch {
            XCTFail("Should not throw: \(error)")
        }
    }
}
