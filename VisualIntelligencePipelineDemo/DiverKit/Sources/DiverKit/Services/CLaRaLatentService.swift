//
//  CLaRaLatentService.swift
//  DiverKit
//
//  Wraps Apple's CLaRa 7B model using pure MLX Swift for agentic search locally on iOS/macOS.
//

import Foundation

#if canImport(MLXLLM) && !targetEnvironment(simulator)
import MLX
import MLXLLM
import MLXLMCommon
#endif

/// Protocol defining Agentic Search capabilities over CLaRa
public protocol LocalAgenticSearching: Sendable {
    var isAvailable: Bool { get }
    func query(documentText: String, question: String) async throws -> String?
}

/// A native MLX Swift service that loads the fused CLaRa 7B model locally
/// and performs text generation/RAG querying.
public final class CLaRaLatentService: LocalAgenticSearching, @unchecked Sendable {
    
    public static let shared = CLaRaLatentService()
    
    public var isAvailable: Bool {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        return FileManager.default.fileExists(atPath: Self.modelCacheDirectory.path)
        #else
        return false
        #endif
    }
    
    private static var modelCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Models/CLaRa")
    }
    
    #if canImport(MLXLLM) && !targetEnvironment(simulator)
    private var container: ModelContainer?
    private let loadLock = NSLock()
    #endif
    
    private var isLoading = false
    
    public init() {}
    
    public func loadModel() async throws {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        guard container == nil else { return }
        
        guard FileManager.default.fileExists(atPath: Self.modelCacheDirectory.path) else {
            throw CLaRaError.modelNotCached
        }
        
        print("📦 [CLaRaLatentService] Loading CLaRa 7B into unified memory...")
        let config = ModelConfiguration(directory: Self.modelCacheDirectory)
        self.container = try await LLMModelFactory.shared.loadContainer(configuration: config)
        print("✅ [CLaRaLatentService] CLaRa 7B loaded.")
        #else
        throw CLaRaError.notSupported
        #endif
    }
    
    public func query(documentText: String, question: String) async throws -> String? {
        guard isAvailable else { return nil }
        
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        isLoading = true
        defer { isLoading = false }
        
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return nil }
            guard !Task.isCancelled else { return nil }
            
            do {
                if self.container == nil {
                    try await self.loadModel()
                }
                guard let container = self.container else { return nil }
                
                let prompt = """
                You are CLaRa, an AI reading assistant. Base your answer strictly on the provided context.
                
                Context:
                \(documentText)
                
                Question:
                \(question)
                
                Answer: 
                """
                
                let lmInput = try await container.processor.prepare(input: UserInput(prompt: prompt))
                let params = GenerateParameters(maxTokens: 256, temperature: 0.1)
                
                let stream = try MLXLMCommon.generate(input: lmInput, parameters: params, context: container)
                
                var output = ""
                for await chunk in stream {
                    switch chunk {
                    case .chunk(let text):
                        output += text
                    default: break
                    }
                }
                
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                print("❌ [CLaRaLatentService] Query failed: \(error)")
                return nil
            }
        }.value
        #else
        return nil
        #endif
    }
    
    public enum CLaRaError: Error, LocalizedError {
        case notSupported
        case modelNotCached
        case generationFailed
        
        public var errorDescription: String? {
            switch self {
            case .notSupported: return "CLaRa is not supported on this platform/simulator."
            case .modelNotCached: return "CLaRa weights are not downloaded."
            case .generationFailed: return "CLaRa inference failed."
            }
        }
    }
}
