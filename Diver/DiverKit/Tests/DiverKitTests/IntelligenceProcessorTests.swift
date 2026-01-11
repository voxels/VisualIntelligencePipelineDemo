import XCTest
import Vision
import CoreVideo
@testable import DiverKit

final class IntelligenceProcessorTests: XCTestCase {
    var processor: IntelligenceProcessor!
    
    override func setUp() {
        super.setUp()
        processor = IntelligenceProcessor()
    }
    
    override func tearDown() {
        processor = nil
        super.tearDown()
    }
    
    // Helper to create a dummy pixel buffer
    private func createDummyBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, attrs, &buffer)
        guard status == kCVReturnSuccess else { return nil }
        return buffer
    }

    func testProcessPipelineStability() async {
        guard let buffer = createDummyBuffer() else {
            XCTFail("Failed to create test buffer")
            return
        }
        
        do {
            // Simply verify it doesn't throw or crash when processing a frame
            _ = try await processor.process(frame: buffer)
            XCTAssertTrue(true)
        } catch {
            XCTFail("Processor should not throw: \(error)")
        }
    }

    func testIntelligenceResultMetadata() {
        // Test all result types and their metadata extensions
        let qrURL = URL(string: "https://apple.com")!
        let qr = IntelligenceResult.qr(qrURL)
        XCTAssertEqual(qr.title, "QR Code Found")
        XCTAssertEqual(qr.subtitle, qrURL.absoluteString)
        XCTAssertEqual(qr.icon, "qrcode")
        
        let product = IntelligenceResult.product(code: "12345", type: .upc)
        XCTAssertEqual(product.title, "Product Detected")
        XCTAssertEqual(product.subtitle, "UPC: 12345")
        XCTAssertEqual(product.icon, "barcode.viewfinder")
        XCTAssertEqual(product.secondaryAction?.title, "Compare Prices")
        
        let movie = IntelligenceResult.entertainment(title: "Inception", type: .movie)
        XCTAssertEqual(movie.title, "Inception")
        XCTAssertEqual(movie.subtitle, "Movie Poster")
        XCTAssertEqual(movie.icon, "film")
        XCTAssertEqual(movie.secondaryAction?.title, "Watch Trailer")
        
        let concert = IntelligenceResult.entertainment(title: "Met Gala", type: .concert)
        XCTAssertEqual(concert.subtitle, "Concert Flyer")
        XCTAssertEqual(concert.icon, "music.mic")
        XCTAssertEqual(concert.secondaryAction?.title, "Book Tickets")
        
        let semantic = IntelligenceResult.semantic("cat", confidence: 0.9)
        XCTAssertEqual(semantic.title, "Cat")
        XCTAssertEqual(semantic.icon, "brain")
    }
    
    func testEntertainmentSecondaryActionURLs() {
        let movie = IntelligenceResult.entertainment(title: "The Matrix", type: .movie)
        
        let concert = IntelligenceResult.entertainment(title: "Coachella", type: .concert)
        XCTAssertTrue(concert.secondaryAction?.url.contains("ticketmaster") ?? false, "Concert action should link to Ticketmaster")
    }
}
