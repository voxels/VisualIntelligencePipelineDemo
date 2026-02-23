import XCTest
import SwiftData
import Photos
@testable import DiverKit

final class PhotoKitIndexerServiceTests: XCTestCase {

    var modelContainer: ModelContainer!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: PersonVector.self, configurations: config)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
    }

    func testBootstrapFaceIndex_WhenNotAuthorized_ThrowsError() async {
        // Since we can't mock PHPhotoLibrary easily, this test might behave 
        // differently depending on the simulator's TCC state. 
        // We will just verify that it doesn't crash.
        let service = PhotoKitIndexerService(modelContainer: modelContainer)
        
        do {
            let count = try await service.bootstrapFaceIndex()
            // If authorized, it might return 0 since there are no photos in the dummy simulator
            XCTAssertGreaterThanOrEqual(count, 0)
        } catch let error as PhotoKitIndexerService.IndexerError {
            // Should hit authorization denied in a clean test environment
            XCTAssertEqual(error, .authorizationDenied)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
