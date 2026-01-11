import XCTest
@testable import DiverShared

final class DiverItemDescriptorTests: XCTestCase {
    func testPreferredListLabelUsesProvidedValue() {
        let descriptor = DiverItemDescriptor(
            id: "1",
            url: "https://example.com",
            title: "Example",
            styleTags: ["cozy"],
            categories: ["Coffee"]
        )

        XCTAssertEqual(descriptor.preferredListLabel(preferred: "Favorites"), "Favorites")
    }

    func testPreferredListLabelFallsBackToCategory() {
        let descriptor = DiverItemDescriptor(
            id: "1",
            url: "https://example.com",
            title: "Example",
            styleTags: [],
            categories: ["  sushi  "]
        )

        XCTAssertEqual(descriptor.preferredListLabel(preferred: nil as String?), "sushi")
    }

    func testPreferredListLabelFallsBackToStyleTag() {
        let descriptor = DiverItemDescriptor(
            id: "1",
            url: "https://example.com",
            title: "Example",
            styleTags: ["  cozy  "],
            categories: []
        )

        XCTAssertEqual(descriptor.preferredListLabel(preferred: nil as String?), "cozy")
    }

    func testPreferredListLabelUsesDefaultOtherwise() {
        let descriptor = DiverItemDescriptor(
            id: "1",
            url: "https://example.com",
            title: "Example",
            styleTags: [],
            categories: []
        )

        XCTAssertEqual(descriptor.preferredListLabel(preferred: nil as String?), DiverListLabel.default)
    }
}
