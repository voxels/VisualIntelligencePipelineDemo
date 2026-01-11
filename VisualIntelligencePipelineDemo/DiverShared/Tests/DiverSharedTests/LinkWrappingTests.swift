import XCTest
@testable import DiverShared

final class LinkWrappingTests: XCTestCase {
    private let secret = Data("unit-test-secret".utf8)

    func testStableID() {
        let url = URL(string: "https://example.com/page?x=1")!
        let id1 = DiverLinkWrapper.id(for: url)
        let id2 = DiverLinkWrapper.id(for: url)
        XCTAssertEqual(id1, id2)
    }

    func testSaltChangesID() {
        let url = URL(string: "https://example.com/page?x=1")!
        let id1 = DiverLinkWrapper.id(for: url, salt: "a")
        let id2 = DiverLinkWrapper.id(for: url, salt: "b")
        XCTAssertNotEqual(id1, id2)
    }

    func testWrapAndResolvePayload() throws {
        let url = URL(string: "https://example.com/page?x=1")!
        let payload = DiverLinkPayload(url: url, title: "Example")
        let wrapped = try DiverLinkWrapper.wrap(url: url, secret: secret, payload: payload)
        let resolved = try DiverLinkWrapper.resolvePayload(from: wrapped, secret: secret)
        XCTAssertEqual(resolved, payload)
        XCTAssertEqual(resolved?.resolvedURL, url)
    }

    func testResolveWithoutPayloadReturnsNil() throws {
        let url = URL(string: "https://example.com/page?x=1")!
        let wrapped = try DiverLinkWrapper.wrap(url: url, secret: secret, includePayload: false)
        let resolved = try DiverLinkWrapper.resolvePayload(from: wrapped, secret: secret)
        XCTAssertNil(resolved)
    }

    func testSignatureValidationFailsOnTamper() throws {
        let url = URL(string: "https://example.com/page?x=1")!
        let payload = DiverLinkPayload(url: url)
        let wrapped = try DiverLinkWrapper.wrap(url: url, secret: secret, payload: payload)

        var components = URLComponents(url: wrapped, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items = items.map { item in
            if item.name == "p" {
                return URLQueryItem(name: item.name, value: "tampered")
            }
            return item
        }
        components.queryItems = items
        let tampered = components.url!

        XCTAssertThrowsError(try DiverLinkWrapper.resolvePayload(from: tampered, secret: secret)) { error in
            XCTAssertEqual(error as? DiverLinkError, .invalidSignature)
        }
    }
}
