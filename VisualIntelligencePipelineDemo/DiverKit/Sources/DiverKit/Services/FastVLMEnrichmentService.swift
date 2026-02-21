import Foundation
import CoreGraphics
import CoreImage
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
    /// The HuggingFace ID or local identifier of the model used to generate this
    public let modelID: String?
    
    public init(
        imageDescription: String? = nil,
        contextSummary: String? = nil,
        suggestedTitle: String? = nil,
        suggestedPurpose: String? = nil,
        suggestedTags: [String] = [],
        statements: [String] = [],
        modelID: String? = nil
    ) {
        self.imageDescription = imageDescription
        self.contextSummary = contextSummary
        self.suggestedTitle = suggestedTitle
        self.suggestedPurpose = suggestedPurpose
        self.suggestedTags = suggestedTags
        self.statements = statements
        self.modelID = modelID
    }
}

// MARK: - Service

/// On-device FastVLM enrichment service using MLX Swift (VLM only).
/// Provides multimodal image understanding as an additive enrichment step.
/// Model is opt-in: user must enable and download via Settings.
/// Safety: @unchecked Sendable — mutable `container` guarded by `loadLock` (NSLock),
/// `isLoading`/`retainModel`/`memoryPressureSource` accessed from single-consumer patterns.
public final class FastVLMEnrichmentService: FastVLMAnalyzing, Sendable {
    
    // MARK: - Configuration
    
    /// HuggingFace model identifier for Apple FastVLM.
    /// Dynamically resolves to the highest tier model downloaded by the user via EdgeDaemon,
    /// or falls back to the default 0.5B model.
    public static var modelID: String {
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Models/FastVLM")
        
        guard let dir = modelsDir else { return "mlx-community/FastVLM-0.5B-bf16" }
        
        let capability = CapabilityRouter.shared
        
        // 1. If we can run heavy VLM (16GB+ RAM), prefer 7B, then fallback.
        if capability.canRunHeavyVLM {
            let config7B = dir.appendingPathComponent("7B/config.json").path
            if FileManager.default.fileExists(atPath: config7B) {
                print("🧠 [FastVLMService] Resolved heavy model capability: apple/FastVLM/7B")
                return "apple/FastVLM/7B"
            }
        }
        
        // 2. If we can run light VLM (8GB+ RAM), or as a fallback for 7B, try 0.5B.
        if capability.canRunLightVLM {
            let config05B = dir.appendingPathComponent("0.5B/config.json").path
            if FileManager.default.fileExists(atPath: config05B) {
                print("🧠 [FastVLMService] Resolved light model capability: apple/FastVLM/0.5B")
                return "apple/FastVLM/0.5B"
            }
        }
        
        // 3. Fallback to default community model if local weights aren't downloaded or RAM is too low.
        return "mlx-community/FastVLM-0.5B-bf16"
    }
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
    
    /// Instance-level availability check (protocol conformance)
    public var isAvailable: Bool { Self.isAvailable }
    
    /// The directory where the active model is stored.
    private static var modelCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let activeID = Self.modelID
        
        // If it's our downloaded Apple FastVLM models, they live in Models/FastVLM/Tier
        if activeID.starts(with: "apple/FastVLM/") {
            let tier = activeID.replacingOccurrences(of: "apple/FastVLM/", with: "")
            return appSupport.appendingPathComponent("Models/FastVLM/\(tier)")
        }
        
        // Fallback MLX cache directory for the built-in 0.5B community model
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("models/\(activeID)", isDirectory: true)
    }
    
    // MARK: - Model State (Cached)
    
    #if canImport(MLXVLM) && !targetEnvironment(simulator)
    nonisolated(unsafe) private var container: ModelContainer?
    private let loadLock = NSLock()
    #endif
    
    /// Whether the model is busy (loading or analyzing) — guards memory pressure unloading
    nonisolated(unsafe) private var isLoading = false
    
    /// When true, suppresses memory-pressure unloading (e.g. during batch queue processing).
    /// Only `.critical` pressure will force an unload while retained.
    nonisolated(unsafe) public var retainModel: Bool = false
    
    /// GCD memory pressure source — auto-unloads model when OS signals pressure
    nonisolated(unsafe) private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Init / Deinit
    
    public init() {
        startMemoryPressureMonitor()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
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
            print("⚠️ [FastVLMService] Memory pressure detected — scheduling model unload")
            // Unload on a detached task to avoid blocking any thread during GPU resource deallocation
            Task.detached(priority: .background) { [weak self] in
                self?.unloadModel()
            }
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
        
        let config: ModelConfiguration
        if Self.modelID.starts(with: "apple/FastVLM/") {
            // Use local weights directory for the downloaded EdgeDaemon models
            config = ModelConfiguration(
                directory: Self.modelCacheDirectory
            )
        } else {
            config = ModelConfiguration(id: Self.modelID)
        }
        
        self.container = try await VLMModelFactory.shared.loadContainer(
            configuration: config
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
        
        let config: ModelConfiguration
        if Self.modelID.starts(with: "apple/FastVLM/") {
            config = ModelConfiguration(directory: Self.modelCacheDirectory)
        } else {
            config = ModelConfiguration(id: Self.modelID)
        }
        
        self.container = try await VLMModelFactory.shared.loadContainer(
            configuration: config
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
    
    // MARK: - Single-Pass Grounded Analysis
    
    /// Run grounded FastVLM analysis: image + Vision framework tags + enrichment context in one pass.
    /// The Vision tags anchor the model to prevent hallucination; the image provides visual detail.
    /// - Parameters:
    ///   - image: The source image (prefer sifted/subject-only when available)
    ///   - visionTags: Classification labels from Vision framework (grounding anchors)
    ///   - enrichmentContext: Structured context from other enrichment services
    ///   - transcription: OCR text if available
    /// - Returns: Structured `FastVLMAnalysis` with grounded descriptions
    public func analyze(
        image: CGImage?,
        visionTags: [String] = [],
        enrichmentContext: String,
        transcription: String? = nil
    ) async throws -> FastVLMAnalysis? {
        guard Self.isAvailable else { return nil }
        
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        isLoading = true
        defer { isLoading = false }
        
        // Run model loading AND inference at background priority to avoid starving the main thread.
        // GPU/CPU-intensive model loading and inference saturates all cores; lowering priority
        // lets the OS scheduler keep the UI responsive.
        let capturedImage = image
        let capturedTags = visionTags
        let capturedContext = enrichmentContext
        let capturedTranscription = transcription
        let result: FastVLMAnalysis? = await Task.detached(priority: .background) { [self] in
            // Bail immediately if the parent task was cancelled (e.g. app backgrounded).
            // This prevents submitting new Metal command buffers after iOS has invalidated them.
            guard !Task.isCancelled else {
                print("⏭️ [FastVLM] Skipping inference — task cancelled (app backgrounded)")
                return nil
            }
            
            // Load model in background — GPU allocation can take 100ms+
            let container: ModelContainer
            do {
                container = try await self.ensureLoaded()
            } catch {
                print("❌ [FastVLM] Failed to load model: \(error)")
                return nil
            }
            
            let analysisText: String?
            
            if let capturedImage {
                // Single-pass: image + grounding data → structured output
                analysisText = try? await runGroundedAnalysis(
                    image: capturedImage,
                    visionTags: capturedTags,
                    enrichmentContext: capturedContext,
                    transcription: capturedTranscription,
                    container: container
                )
            } else if !capturedContext.isEmpty {
                // Text-only fallback (e.g. link items with no image)
                analysisText = try? await runTextOnlyAnalysis(
                    enrichmentContext: capturedContext,
                    transcription: capturedTranscription,
                    container: container
                )
            } else {
                analysisText = nil
            }
            
            // If we got nothing, return nil
            guard let analysisText else { return nil }
            
            // Parse structured fields from FastVLM output
            return Self.parseStructuredOutput(analysisText)
        }.value
        
        print("✅ [FastVLMService] Grounded analysis complete — hasImage: \(image != nil), visionTags: \(visionTags.count), result: \(result != nil)")
        return result
        
        #else
        return nil
        #endif
    }
    
    // MARK: - Analysis Methods
    
    public static func buildGroundedPrompt(
        visionTags: [String],
        enrichmentContext: String,
        transcription: String?
    ) -> String {
        var prompt = """
        Analyze this image and provide a structured description.
        """
        
        if !visionTags.isEmpty {
            prompt += "\nThis image has been classified as containing: \(visionTags.prefix(10).joined(separator: ", "))."
        }
        
        if let transcription, !transcription.isEmpty {
            prompt += "\nVisible text detected: \(String(transcription.prefix(500)))"
        }
        
        if !enrichmentContext.isEmpty {
            prompt += "\nAdditional context: \(String(enrichmentContext.prefix(1000)))"
        }
        
        prompt += """
        
        
        Respond in this exact format:
        TITLE: [short descriptive title of what is shown]
        SUMMARY: [one sentence describing only what you can confirm seeing]
        PURPOSE: [the user's likely intent for capturing this]
        TAGS: [tag1, tag2, tag3]
        STATEMENTS:
        - [specific observation about what is visible]
        - [specific observation about what is visible]
        
        Only describe what you can directly see. Do not speculate. If unsure, say "unknown".
        """
        
        return prompt
    }
    
    #if canImport(MLXVLM) && !targetEnvironment(simulator)
    /// Single-pass grounded image analysis: sends the image to the VLM alongside
    /// Vision framework tags as anchoring context to prevent hallucination.
    private func runGroundedAnalysis(
        image: CGImage,
        visionTags: [String],
        enrichmentContext: String,
        transcription: String?,
        container: ModelContainer
    ) async throws -> String? {
        print("🧠 [FastVLMService] Starting grounded image analysis (tags: \(visionTags.count))")
        
        let finalPrompt = Self.buildGroundedPrompt(
            visionTags: visionTags,
            enrichmentContext: enrichmentContext,
            transcription: transcription
        )

        let result: String = try await container.perform { context in
            let ciImage = CIImage(cgImage: image)
            let imageInput = UserInput.Image.ciImage(ciImage)
            let lmInput = try await context.processor.prepare(input: UserInput(prompt: finalPrompt, images: [imageInput]))
            let params = GenerateParameters(maxTokens: 128, temperature: 0.0)
            let stream = try MLXLMCommon.generate(
                input: lmInput, parameters: params, context: context
            )
            var output = ""
            for await generation in stream {
                if case .chunk(let text) = generation {
                    output += text
                    if output.count > 512 { break }
                }
            }
            return output
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        print("✅ [FastVLMService] Grounded image analysis: \(trimmed.count) chars")
        return trimmed
    }
    #endif
    
    public static func buildTextOnlyPrompt(
        enrichmentContext: String,
        transcription: String?
    ) -> String {
        var prompt = """
        Analyze the following data about a captured item.
        
        Respond in this exact format:
        TITLE: [short descriptive title]
        SUMMARY: [one sentence summary]
        PURPOSE: [the user's likely intent]
        TAGS: [tag1, tag2, tag3]
        
        Context Data:
        \(String(enrichmentContext.prefix(2000)))
        """
        
        if let transcription, !transcription.isEmpty {
            prompt += "\n\nOCR Text:\n\(String(transcription.prefix(500)))"
        }
        
        return prompt
    }

    #if canImport(MLXVLM) && !targetEnvironment(simulator)
    /// Text-only fallback for items without images (links, QR codes, etc.)
    private func runTextOnlyAnalysis(
        enrichmentContext: String,
        transcription: String?,
        container: ModelContainer
    ) async throws -> String? {
        print("🧠 [FastVLMService] Starting text-only analysis (no image)")
        
        let finalPrompt = Self.buildTextOnlyPrompt(
            enrichmentContext: enrichmentContext,
            transcription: transcription
        )

        let result: String = try await container.perform { context in
            let lmInput = try await context.processor.prepare(input: UserInput(prompt: finalPrompt))
            let params = GenerateParameters(maxTokens: 128, temperature: 0.0)
            let stream = try MLXLMCommon.generate(
                input: lmInput, parameters: params, context: context
            )
            var output = ""
            for await generation in stream {
                if case .chunk(let text) = generation {
                    output += text
                    if output.count > 512 { break }
                }
            }
            return output
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        print("✅ [FastVLMService] Text-only analysis: \(trimmed.count) chars")
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
    public static func parseStructuredOutput(_ text: String?) -> FastVLMAnalysis? {
        guard let text, !text.isEmpty else { return nil }
        
        var title: String?
        var summary: String?
        var purpose: String?
        var tags: [String] = []
        var statements: [String] = []
        
        let lines = text.components(separatedBy: "\n")
        var inStatements = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("TITLE:") {
                title = trimmed.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
                inStatements = false
            } else if trimmed.hasPrefix("SUMMARY:") {
                summary = trimmed.replacingOccurrences(of: "SUMMARY:", with: "").trimmingCharacters(in: .whitespaces)
                inStatements = false
            } else if trimmed.hasPrefix("PURPOSE:") {
                purpose = trimmed.replacingOccurrences(of: "PURPOSE:", with: "").trimmingCharacters(in: .whitespaces)
                inStatements = false
            } else if trimmed.hasPrefix("TAGS:") {
                let tagString = trimmed.replacingOccurrences(of: "TAGS:", with: "").trimmingCharacters(in: .whitespaces)
                tags = tagString
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
                    statements.append(statement)
                }
            }
        }
        
        return FastVLMAnalysis(
            imageDescription: summary,
            contextSummary: summary ?? text,
            suggestedTitle: title,
            suggestedPurpose: purpose,
            suggestedTags: tags,
            statements: statements,
            modelID: Self.modelID
        )
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
