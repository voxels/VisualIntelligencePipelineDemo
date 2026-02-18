import Testing
import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
@testable import DiverKit

// MARK: - Mock Implementations

/// Mock conforming to IntelligenceProcessing for DI testing.
final class MockIntelligenceProcessor: IntelligenceProcessing, @unchecked Sendable {
    var processCallCount = 0
    var stubbedResults: [IntelligenceResult] = []
    var errorToThrow: Error?
    
    func process(frame: CVPixelBuffer, orientation: CGImagePropertyOrientation, mode: IntelligenceProcessor.AnalysisMode) async throws -> [IntelligenceResult] {
        processCallCount += 1
        if let error = errorToThrow { throw error }
        return stubbedResults
    }
    
    func process(image: CGImage, orientation: CGImagePropertyOrientation, mode: IntelligenceProcessor.AnalysisMode) async throws -> [IntelligenceResult] {
        processCallCount += 1
        if let error = errorToThrow { throw error }
        return stubbedResults
    }
}

/// Mock conforming to ContextProcessing for DI testing.
final class MockContextProcessor: ContextProcessing, Sendable {
    let stubbedSummary: String?
    let stubbedStatements: [String]
    let stubbedPurpose: String?
    let stubbedTags: [String]
    let stubbedSummarizeResult: String
    
    init(
        summary: String? = "Mock summary",
        statements: [String] = ["statement1"],
        purpose: String? = "testing",
        tags: [String] = ["mock"],
        summarizeResult: String = "Summarized text"
    ) {
        self.stubbedSummary = summary
        self.stubbedStatements = statements
        self.stubbedPurpose = purpose
        self.stubbedTags = tags
        self.stubbedSummarizeResult = summarizeResult
    }
    
    func processContext(from data: EnrichmentData, sessionID: String?) async throws -> (summary: String?, statements: [String], purpose: String?, tags: [String]) {
        return (stubbedSummary, stubbedStatements, stubbedPurpose, stubbedTags)
    }
    
    func summarizeText(_ text: String) async throws -> String {
        return stubbedSummarizeResult
    }
}

/// Mock conforming to AestheticsScoring for DI testing.
final class MockAestheticsScorer: AestheticsScoring, @unchecked Sendable {
    var extractCallCount = 0
    var bestThumbnailCallCount = 0
    var stubbedFrames: [Thumbnail] = []
    
    func extractBestFrames(from videoURL: URL, count: Int) async throws -> [Thumbnail] {
        extractCallCount += 1
        return Array(stubbedFrames.prefix(count))
    }
    
    func bestThumbnailFromImage(_ cgImage: CGImage) async throws -> Thumbnail {
        bestThumbnailCallCount += 1
        return Thumbnail(image: cgImage, frame: nil, score: 0.85)
    }
}

// MARK: - Protocol Conformance Tests

@Suite("Service Protocol Conformance")
struct ServiceProtocolConformanceTests {
    
    // MARK: - IntelligenceProcessing
    
    @Test("IntelligenceProcessor conforms to IntelligenceProcessing")
    func intelligenceProcessorConformance() {
        let processor: any IntelligenceProcessing = IntelligenceProcessor()
        #expect(processor is IntelligenceProcessor)
    }
    
    @Test("Mock IntelligenceProcessing returns stubbed results")
    func mockIntelligenceProcessing() async throws {
        let mock = MockIntelligenceProcessor()
        mock.stubbedResults = [.text("hello")]
        
        // Create a minimal 1x1 CGImage for testing
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        
        let results = try await mock.process(image: image, orientation: .up, mode: .fullAnalysis)
        #expect(results.count == 1)
        #expect(mock.processCallCount == 1)
    }
    
    // MARK: - ContextProcessing
    
    @Test("ContextQuestionService conforms to ContextProcessing")
    func contextServiceConformance() {
        let service: any ContextProcessing = ContextQuestionService()
        #expect(service is ContextQuestionService)
    }
    
    @Test("Mock ContextProcessing returns stubbed results")
    func mockContextProcessing() async throws {
        let mock = MockContextProcessor(summary: "Test", statements: ["a", "b"], purpose: "demo", tags: ["tag1"])
        let data = EnrichmentData(title: "Test item")
        
        let result = try await mock.processContext(from: data, sessionID: nil)
        #expect(result.summary == "Test")
        #expect(result.statements == ["a", "b"])
        #expect(result.purpose == "demo")
        #expect(result.tags == ["tag1"])
    }
    
    @Test("Mock ContextProcessing summarizeText returns stub")
    func mockSummarize() async throws {
        let mock = MockContextProcessor(summarizeResult: "Brief summary")
        let result = try await mock.summarizeText("Long text...")
        #expect(result == "Brief summary")
    }
    
    // MARK: - AestheticsScoring
    
    @Test("Mock AestheticsScoring tracks calls and returns stubs")
    func mockAestheticsScoring() async throws {
        let mock = MockAestheticsScorer()
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        
        let thumb = try await mock.bestThumbnailFromImage(image)
        #expect(thumb.score == 0.85)
        #expect(mock.bestThumbnailCallCount == 1)
    }
    
    // MARK: - FastVLMAnalyzing
    
    @Test("MockFastVLMService conforms to FastVLMAnalyzing")
    func fastVLMConformance() {
        let service: any FastVLMAnalyzing = MockFastVLMService()
        #expect(service.isAvailable == true)
        #expect(service.isModelLoaded == false)
    }
    
    @Test("MockFastVLMService tracks lifecycle correctly")
    func fastVLMLifecycle() async throws {
        let mock = MockFastVLMService()
        
        // Initially not loaded
        #expect(!mock.isModelLoaded)
        
        // Load
        try await mock.loadModel()
        #expect(mock.isModelLoaded)
        
        // Analyze
        mock.analyzeResult = FastVLMAnalysis(
            imageDescription: "A test image",
            contextSummary: nil,
            suggestedTitle: "Test",
            suggestedPurpose: nil,
            suggestedTags: [],
            statements: []
        )
        let result = try await mock.analyze(image: nil, visionTags: [], enrichmentContext: "test")
        #expect(result?.imageDescription == "A test image")
        #expect(mock.analyzeCallCount == 1)
        
        // Delete
        try mock.deleteModel()
        #expect(!mock.isModelLoaded)
    }
    
    @Test("MockFastVLMService error propagation")
    func fastVLMErrorPropagation() async {
        let mock = MockFastVLMService()
        struct TestError: Error {}
        mock.errorToThrow = TestError()
        
        do {
            _ = try await mock.analyze(image: nil, visionTags: [], enrichmentContext: "")
            #expect(Bool(false), "Expected error to be thrown")
        } catch {
            #expect(error is TestError)
        }
    }
    
    // MARK: - Protocol erasure (type-erased usage)
    
    @Test("Protocols enable type-erased dependency injection")
    func typeErasedInjection() async throws {
        // Verify all protocols can be stored as existentials
        let intelligence: any IntelligenceProcessing = MockIntelligenceProcessor()
        let context: any ContextProcessing = MockContextProcessor()
        let aesthetics: any AestheticsScoring = MockAestheticsScorer()
        let vlm: any FastVLMAnalyzing = MockFastVLMService()
        
        // All should be usable through protocol interface
        #expect(vlm.isAvailable)
        let summarized = try await context.summarizeText("hello")
        #expect(!summarized.isEmpty)
        
        _ = intelligence
        _ = aesthetics
    }
}
