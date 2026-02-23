import XCTest
@testable import DiverKit

#if os(macOS)
final class MLSharpServiceTests: XCTestCase {

    var service: MLSharpService!

    override func setUp() {
        super.setUp()
        service = MLSharpService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testProcessImage_WhenRepoMissing_ThrowsError() async {
        // We simulate a failure by passing empty data. The service should fail 
        // to find the Python virtual environment or the python script in a sandboxed CI test environment,
        // and throw EdgeInferenceError.serviceUnavailable.
        let dummyData = Data("dummy".utf8)
        
        do {
            _ = try await service.processImage(imageData: dummyData)
            XCTFail("Expected service to throw due to missing ml-sharp path or venv in test environment.")
        } catch EdgeInferenceError.serviceUnavailable(let message) {
            // Expected
            XCTAssertTrue(message.contains("ml-sharp"), "Error message should mention ml-sharp")
        } catch {
            XCTFail("Unexpected error type thrown: \(error)")
        }
    }
}
#endif
