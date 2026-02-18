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
/// Safety: @unchecked Sendable — mutable `container` guarded by `loadLock` (NSLock),
/// `isLoading`/`retainModel`/`memoryPressureSource` accessed from single-consumer patterns.
public final class FastVLMEnrichmentService: FastVLMAnalyzing, @unchecked Sendable {
    
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
    
    /// Instance-level availability check (protocol conformance)
    public var isAvailable: Bool { Self.isAvailable }
    
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
        let container = try await ensureLoaded()
        isLoading = true
        defer { isLoading = false }
        
        // Run MLX inference at background priority to avoid starving the main thread.
        // GPU/CPU-intensive model inference saturates all cores; lowering priority
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
            let parsed = parseStructuredOutput(analysisText)
            
            return FastVLMAnalysis(
                imageDescription: parsed.summary,
                contextSummary: parsed.summary ?? analysisText,
                suggestedTitle: parsed.title,
                suggestedPurpose: parsed.purpose,
                suggestedTags: parsed.tags,
                statements: parsed.statements
            )
        }.value
        
        print("✅ [FastVLMService] Grounded analysis complete — hasImage: \(image != nil), visionTags: \(visionTags.count), result: \(result != nil)")
        return result
        
        #else
        return nil
        #endif
    }
    
    // MARK: - Analysis Methods
    
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
        
        // Build grounded prompt — anchor the model with what Vision already confirmed
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
        
        let finalPrompt = prompt
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
    
    /// Text-only fallback for items without images (links, QR codes, etc.)
    private func runTextOnlyAnalysis(
        enrichmentContext: String,
        transcription: String?,
        container: ModelContainer
    ) async throws -> String? {
        print("🧠 [FastVLMService] Starting text-only analysis (no image)")
        
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
        
        let finalPrompt = prompt
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
