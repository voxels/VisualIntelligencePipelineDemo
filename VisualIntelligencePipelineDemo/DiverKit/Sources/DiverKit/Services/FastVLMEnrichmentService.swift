import Foundation
import CoreGraphics
import Dispatch
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MLXVLM) && !targetEnvironment(simulator)
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
#endif

// MARK: - Structured Output

/// Structured output from FastVLM analysis, stored on `ProcessedItem`.
public struct FastVLMAnalysis: Codable, Sendable, Equatable {
    /// Multimodal description of the image content
    public let imageDescription: String?
    /// Contextual summary synthesized from enrichment data
    public let contextSummary: String?
    /// Model-suggested title
    public let suggestedTitle: String?
    /// Model-suggested purpose/intent
    public let suggestedPurpose: String?
    /// Model-suggested tags
    public let suggestedTags: [String]
    /// Combined context statements (visual + location + enrichment unified)
    public let statements: [String]
    
    public init(
        imageDescription: String? = nil,
        contextSummary: String? = nil,
        suggestedTitle: String? = nil,
        suggestedPurpose: String? = nil,
        suggestedTags: [String] = [],
        statements: [String] = []
    ) {
        self.imageDescription = imageDescription
        self.contextSummary = contextSummary
        self.suggestedTitle = suggestedTitle
        self.suggestedPurpose = suggestedPurpose
        self.suggestedTags = suggestedTags
        self.statements = statements
    }
}

// MARK: - Service

/// On-device FastVLM enrichment service using MLX Swift (VLM only).
/// Provides multimodal image understanding as an additive enrichment step.
/// Model is opt-in: user must enable and download via Settings.
public final class FastVLMEnrichmentService: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// HuggingFace model identifier for Apple FastVLM 0.5B (~500MB, optimized for on-device inference)
    public static let modelID = "mlx-community/FastVLM-0.5B-bf16"
    
    /// UserDefaults key for opt-in toggle
    private static let enabledKey = "fastvlm_enrichment_enabled"
    
    /// Whether the user has enabled FastVLM enrichment in Settings
    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }
    
    /// Enable or disable FastVLM enrichment
    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }
    
    /// Whether the model is downloaded and ready for inference.
    /// Checks for `config.json` as a sentinel — HF Hub writes this last, so if present the download completed.
    public static var isModelCached: Bool {
        let configFile = modelCacheDirectory.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configFile.path)
    }
    
    /// Whether the service can run (enabled + model cached)
    public static var isAvailable: Bool {
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        return isEnabled && isModelCached
        #else
        return false
        #endif
    }
    
    /// HuggingFace Hub cache directory for this model
    /// defaultHubApi sets downloadBase = cachesDirectory; localRepoLocation = downloadBase/models/<id>
    private static var modelCacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("models/\(modelID)", isDirectory: true)
    }
    
    // MARK: - Model State (Cached)
    
    #if canImport(MLXVLM) && !targetEnvironment(simulator)
    private var container: ModelContainer?
    private let loadLock = NSLock()
    #endif
    
    /// Whether the model is busy (loading or analyzing) — guards memory pressure unloading
    private var isLoading = false
    
    /// When true, suppresses memory-pressure unloading (e.g. during batch queue processing).
    /// Only `.critical` pressure will force an unload while retained.
    public var retainModel: Bool = false
    
    /// GCD memory pressure source — auto-unloads model when OS signals pressure
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Init / Deinit
    
    public init() {
        startMemoryPressureMonitor()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isLoading else {
                print("⚠️ [FastVLMService] Memory pressure detected but model is busy — deferring unload")
                return
            }
            let event = source.data
            if self.retainModel && !event.contains(.critical) {
                print("⚠️ [FastVLMService] Memory pressure detected but model retained for batch — deferring unload")
                return
            }
            print("⚠️ [FastVLMService] Memory pressure detected — unloading model")
            self.unloadModel()
        }
        source.resume()
        memoryPressureSource = source
    }
    
    /// Whether the model is loaded into GPU memory and ready for inference
    public var isModelLoaded: Bool {
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        return container != nil
        #else
        return false
        #endif
    }

    // MARK: - Model Management
    
    /// Load the VLM into GPU memory. Call once at app launch.
    /// Subsequent calls are no-ops if already loaded.
    public func loadModel() async throws {
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        guard !isModelLoaded else {
            print("✅ [FastVLMService] Model already loaded")
            return
        }
        
        guard Self.isModelCached else {
            print("⚠️ [FastVLMService] Model not cached, cannot load")
            return
        }
        
        // Cap MLX GPU buffer cache to 256 MB to reduce memory pressure
        GPU.set(cacheLimit: 256 * 1024 * 1024)
        
        print("📦 [FastVLMService] Loading model into GPU memory...")
        let modelConfig = ModelConfiguration(id: Self.modelID)
        self.container = try await VLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        )
        print("✅ [FastVLMService] Model loaded and cached in GPU memory")
        #else
        throw FastVLMError.notSupported
        #endif
    }
    
    /// Ensure model is loaded, loading if necessary. Thread-safe.
    #if canImport(MLXVLM) && !targetEnvironment(simulator)
    private func ensureLoaded() async throws -> ModelContainer {
        if let container {
            return container
        }
        try await loadModel()
        guard let container else {
            throw FastVLMError.modelNotLoaded
        }
        return container
    }
    #endif
    
    /// Download the FastVLM model from HuggingFace if not already cached.
    /// - Parameter progress: Callback with download progress (0.0 to 1.0)
    public func ensureModelAvailable(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !Self.isModelCached else {
            progress(1.0)
            return
        }
        
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        print("📥 [FastVLMService] Starting model download: \(Self.modelID)")
        
        let modelConfig = ModelConfiguration(id: Self.modelID)
        self.container = try await VLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        ) { update in
            Task { @MainActor in
                progress(update.fractionCompleted)
            }
        }
        
        print("✅ [FastVLMService] Model downloaded and ready: \(Self.modelID)")
        #else
        throw FastVLMError.notSupported
        #endif
    }
    
    /// Delete the cached model to reclaim storage
    public func deleteModel() throws {
        let modelDir = Self.modelCacheDirectory
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
            print("🗑️ [FastVLMService] Model cache deleted")
        }
        
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        container = nil
        #endif
    }
    
    /// Unload the model from GPU memory without deleting the cache
    public func unloadModel() {
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        container = nil
        print("💤 [FastVLMService] Model unloaded from GPU memory")
        #endif
    }
    
    // MARK: - Full Analysis (Image + Context Sequential)
    
    /// Run full FastVLM analysis: multimodal image analysis THEN context synthesis.
    /// Sequential execution reduces peak memory by avoiding two concurrent KV caches.
    /// - Parameters:
    ///   - image: The source image (if available)
    ///   - enrichmentContext: Structured context from other enrichment services
    ///   - transcription: OCR text if available
    /// - Returns: Structured `FastVLMAnalysis` combining both analyses
    public func analyze(
        image: CGImage?,
        enrichmentContext: String,
        transcription: String? = nil
    ) async throws -> FastVLMAnalysis? {
        guard Self.isAvailable else { return nil }
        
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        let container = try await ensureLoaded()
        isLoading = true
        defer { isLoading = false }
        
        // Run sequentially to avoid two concurrent KV caches in memory
        let imageDesc: String? = if let image {
            try? await runImageAnalysis(image: image, container: container)
        } else {
            nil
        }
        
        let contextSummary: String? = if !enrichmentContext.isEmpty {
            try? await runContextAnalysis(
                context: enrichmentContext,
                transcription: transcription,
                container: container
            )
        } else {
            nil
        }
        
        // If we got nothing from either, return nil
        guard imageDesc != nil || contextSummary != nil else { return nil }
        
        // Parse structured fields from FastVLM's context analysis
        let parsed = parseStructuredOutput(contextSummary)
        
        let analysis = FastVLMAnalysis(
            imageDescription: imageDesc,
            contextSummary: parsed.summary ?? contextSummary,
            suggestedTitle: parsed.title,
            suggestedPurpose: parsed.purpose,
            suggestedTags: parsed.tags,
            statements: parsed.statements
        )
        
        print("✅ [FastVLMService] Full analysis complete — image: \(imageDesc != nil), context: \(contextSummary != nil)")
        return analysis
        
        #else
        return nil
        #endif
    }
    
    // MARK: - Individual Analysis Methods
    
    #if canImport(MLXVLM) && !targetEnvironment(simulator)
    /// Multimodal image analysis using VLM
    private func runImageAnalysis(
        image: CGImage,
        container: ModelContainer
    ) async throws -> String? {
        print("🧠 [FastVLMService] Starting multimodal image analysis")
        
        let prompt = """
        Describe this image in detail. Focus on: objects, text, activities, and anything notable.
        Be specific and factual. Identify brands, products, text content, and activities you can see.
        """
        
        let result: String = try await container.perform { context in
            let ciImage = CIImage(cgImage: image)
            let imageInput = UserInput.Image.ciImage(ciImage)
            let lmInput = try await context.processor.prepare(input: UserInput(prompt: prompt, images: [imageInput]))
            let params = GenerateParameters(maxTokens: 512, temperature: 0.3)
            let stream = try MLXLMCommon.generate(
                input: lmInput, parameters: params, context: context
            )
            var output = ""
            for await generation in stream {
                if case .chunk(let text) = generation {
                    output += text
                    if output.count > 2048 { break }
                }
            }
            return output
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        print("✅ [FastVLMService] Image analysis: \(trimmed.count) chars")
        return trimmed
    }
    
    /// Context synthesis using VLM (text-only mode, same model)
    private func runContextAnalysis(
        context: String,
        transcription: String?,
        container: ModelContainer
    ) async throws -> String? {
        print("🧠 [FastVLMService] Starting context analysis")
        
        var prompt = """
        Analyze the following data about a captured item and provide a structured analysis.
        Combine ALL context (visual, location, environmental, web) into unified insights.
        
        Respond in this exact format:
        TITLE: [A specific, descriptive title]
        SUMMARY: [2-sentence summary of what this capture represents]
        PURPOSE: [The user's likely intent, e.g. "Shopping for camera gear"]
        TAGS: [tag1, tag2, tag3]
        STATEMENTS:
        - [Statement 1 combining visual + context evidence]
        - [Statement 2 combining visual + context evidence]
        - [Statement 3 combining visual + context evidence]
        
        Context Data:
        \(String(context.prefix(4000)))
        """
        
        if let transcription, !transcription.isEmpty {
            prompt += "\n\nOCR Text:\n\(String(transcription.prefix(1000)))"
        }
        
        let userInput = UserInput(prompt: prompt)
        
        let result: String = try await container.perform { [prompt] context in
            let lmInput = try await context.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: 384, temperature: 0.3)
            let stream = try MLXLMCommon.generate(
                input: lmInput, parameters: params, context: context
            )
            var output = ""
            for await generation in stream {
                if case .chunk(let text) = generation {
                    output += text
                    if output.count > 1536 { break }
                }
            }
            return output
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        print("✅ [FastVLMService] Context analysis: \(trimmed.count) chars")
        return trimmed
    }
    #endif
    
    // MARK: - Output Parsing
    
    private struct ParsedOutput {
        var title: String?
        var summary: String?
        var purpose: String?
        var tags: [String] = []
        var statements: [String] = []
    }
    
    /// Parse FastVLM's structured text output into typed fields
    private func parseStructuredOutput(_ text: String?) -> ParsedOutput {
        guard let text, !text.isEmpty else { return ParsedOutput() }
        
        var result = ParsedOutput()
        let lines = text.components(separatedBy: "\n")
        var inStatements = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("TITLE:") {
                result.title = trimmed.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
                inStatements = false
            } else if trimmed.hasPrefix("SUMMARY:") {
                result.summary = trimmed.replacingOccurrences(of: "SUMMARY:", with: "").trimmingCharacters(in: .whitespaces)
                inStatements = false
            } else if trimmed.hasPrefix("PURPOSE:") {
                result.purpose = trimmed.replacingOccurrences(of: "PURPOSE:", with: "").trimmingCharacters(in: .whitespaces)
                inStatements = false
            } else if trimmed.hasPrefix("TAGS:") {
                let tagString = trimmed.replacingOccurrences(of: "TAGS:", with: "").trimmingCharacters(in: .whitespaces)
                result.tags = tagString
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                inStatements = false
            } else if trimmed.hasPrefix("STATEMENTS:") {
                inStatements = true
            } else if inStatements && trimmed.hasPrefix("- ") {
                let statement = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !statement.isEmpty {
                    result.statements.append(statement)
                }
            }
        }
        
        return result
    }
    
    // MARK: - Errors
    
    public enum FastVLMError: Error, LocalizedError {
        case notSupported
        case modelNotLoaded
        case generationFailed
        
        public var errorDescription: String? {
            switch self {
            case .notSupported: return "FastVLM enrichment is not supported on this platform"
            case .modelNotLoaded: return "FastVLM model is not loaded"
            case .generationFailed: return "FastVLM text generation failed"
            }
        }
    }
}
