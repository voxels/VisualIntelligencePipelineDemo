//
//  EdgeComputingTests.swift
//  DiverKitTests
//
//  Tests for edge computing Codable types used in
//  distributed actor communication.
//

import Testing
import Foundation
@testable import DiverKit
import DiverShared

@Suite("Edge Computing Tests")
struct EdgeComputingTests {
    
    // MARK: - EdgeNodeInfo Tests
    
    @Test("EdgeNodeInfo encodes and decodes correctly")
    func edgeNodeInfoCodable() throws {
        let info = EdgeNodeInfo(
            deviceName: "MacBook Pro",
            chipFamily: "M4 Pro",
            neuralEngineTOPS: 38.0,
            physicalMemoryGB: 32,
            availableModels: ["FastVLM-0.5B", "YOLO-v8n"],
            isAvailable: true
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(EdgeNodeInfo.self, from: data)
        
        #expect(decoded.deviceName == "MacBook Pro")
        #expect(decoded.chipFamily == "M4 Pro")
        #expect(decoded.neuralEngineTOPS == 38.0)
        #expect(decoded.physicalMemoryGB == 32)
        #expect(decoded.availableModels.count == 2)
        #expect(decoded.isAvailable == true)
    }
    
    @Test("VisionAnalysisResult encodes all fields")
    func visionAnalysisResultCodable() throws {
        let result = VisionAnalysisResult(
            ocrText: "Test text",
            semanticTags: ["product", "electronics"],
            saliencyMap: SaliencyResult(
                width: 64,
                height: 64,
                heatmap: Array(repeating: Float(0.5), count: 64 * 64),
                salientRegions: [NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
            )
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(VisionAnalysisResult.self, from: data)
        
        #expect(decoded.ocrText == "Test text")
        #expect(decoded.semanticTags.count == 2)
        #expect(decoded.saliencyMap?.salientRegions.count == 1)
    }
    
    @Test("LLMAnalysisResult encodes correctly")
    func llmAnalysisResultCodable() throws {
        let result = LLMAnalysisResult(
            summary: "A product on a shelf",
            statements: ["It is a consumer electronics product"],
            purpose: "shopping",
            tags: ["product", "retail"]
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(LLMAnalysisResult.self, from: data)
        
        #expect(decoded.summary == "A product on a shelf")
        #expect(decoded.statements.count == 1)
        #expect(decoded.tags.count == 2)
    }
    
    @Test("ModelState covers all cases")
    func modelStateValues() {
        let states: [ModelState] = [.notDownloaded, .downloading, .downloaded, .loaded, .error]
        #expect(states.count == 5)
    }
    
    @Test("EdgeNodeStatus round-trips through Codable")
    func edgeNodeStatusCodable() throws {
        let status = EdgeNodeStatus(
            deviceName: "Test Mac",
            connectedClients: 2,
            isProcessing: true
        )
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(EdgeNodeStatus.self, from: data)
        
        #expect(decoded.deviceName == "Test Mac")
        #expect(decoded.connectedClients == 2)
        #expect(decoded.isProcessing == true)
    }
}
