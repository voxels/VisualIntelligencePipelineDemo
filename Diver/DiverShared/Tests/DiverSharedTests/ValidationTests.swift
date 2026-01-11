import XCTest
@testable import DiverShared

final class ValidationTests: XCTestCase {

    func testIsValidURL_withValidURLs() {
        XCTAssertTrue(Validation.isValidURL("http://example.com"))
        XCTAssertTrue(Validation.isValidURL("https://example.com"))
        XCTAssertTrue(Validation.isValidURL("https://www.example.com"))
        XCTAssertTrue(Validation.isValidURL("https://example.com/path/to/resource"))
        XCTAssertTrue(Validation.isValidURL("https://example.com?query=123"))
        XCTAssertTrue(Validation.isValidURL("https://user:password@example.com"))
        XCTAssertTrue(Validation.isValidURL("http://127.0.0.1"))
        XCTAssertTrue(Validation.isValidURL("http://localhost:8080"))
    }

    func testIsValidURL_withInvalidURLs() {
        XCTAssertFalse(Validation.isValidURL(nil))
        XCTAssertFalse(Validation.isValidURL(""))
        XCTAssertFalse(Validation.isValidURL("example.com"))
        XCTAssertFalse(Validation.isValidURL("htp://example.com"))
        XCTAssertFalse(Validation.isValidURL("http//example.com"))
        XCTAssertFalse(Validation.isValidURL("http:/example.com"))
        XCTAssertFalse(Validation.isValidURL("http:example.com"))
        XCTAssertFalse(Validation.isValidURL("just some text"))
        XCTAssertFalse(Validation.isValidURL("www.example.com"))
    }
}
