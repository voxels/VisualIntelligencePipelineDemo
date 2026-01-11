import XCTest
@testable import DiverKit
@testable import DiverShared

final class DiverQueueItemHierarchyTests: XCTestCase {
    func testVisualIntelligenceHierarchyCreation() {
       // Setup Results
       let results: [IntelligenceResult] = [
           .product(code: "B00XPROD", type: .unknown, mediaAssets: []),
           .richWeb(url: URL(string: "https://example.com")!, data: .init()),
           .text("Some OCR Text", nil)
       ]
       
       // Act
       let sessionID = "test-session-123"
       let items = DiverQueueItem.items(intelligenceResults: results, sessionID: sessionID)
       
       // Assert
       // 1. Check Master Item
       let master = items.first { $0.descriptor.categories.contains("master") }
       XCTAssertNotNil(master, "Should find a master item")
       XCTAssertEqual(master?.descriptor.id, master?.descriptor.masterCaptureID, "Master item should reference itself as master")
       XCTAssertEqual(master?.descriptor.sessionID, sessionID, "Master item should have correct session ID")
       
       // Check Master Description for Summary
       let desc = master?.descriptor.descriptionText ?? ""
       XCTAssertTrue(desc.contains("Found Product: B00XPROD"), "Summary should mention product")
       XCTAssertTrue(desc.contains("Found Web Link: URL"), "Summary should mention web link")
       XCTAssertTrue(desc.contains("Some OCR Text"), "Summary should include OCR text")
       
       // 2. Check Children
       // Note: text() with NO url does NOT create a child item, only updates fullText.
       let children = items.filter { $0.descriptor.categories.contains("child") }
       XCTAssertEqual(children.count, 2, "Should have 2 children (product + web)")
       
       for child in children {
           XCTAssertEqual(child.descriptor.masterCaptureID, master?.descriptor.id, "Child should link to master")
           XCTAssertEqual(child.descriptor.sessionID, sessionID, "Child should have correct session ID")
           XCTAssertNotEqual(child.descriptor.id, master?.descriptor.id, "Child ID should differ from Master ID")
       }
       
       let product = children.first { $0.descriptor.type == .product }
       XCTAssertNotNil(product)
       XCTAssertEqual(product?.descriptor.styleTags, ["product"])
       XCTAssertTrue(product?.descriptor.url.starts(with: "diver-product") ?? false, "Product should have fallback URL")
       
       let web = children.first { $0.descriptor.type == .web }
       XCTAssertNotNil(web)
       XCTAssertEqual(web?.descriptor.url, "https://example.com")
    }
}
