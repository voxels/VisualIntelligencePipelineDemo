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
    /// or falls back to the default 0.5B model. Result is cached after first resolution.
    nonisolated(unsafe) private static var _resolvedModelID: String?
    
    public static var modelID: String {
        // Return cached result to avoid repeated resolution logging
        if let cached = _resolvedModelID { return cached }
        
        let resolved = resolveModelID()
        _resolvedModelID = resolved
        return resolved
    }
    
    /// Invalidate the cached model ID (e.g., after downloading a new tier).
    public static func invalidateModelIDCache() {
        _resolvedModelID = nil
    }
    
    private static func resolveModelID() -> String {
        let capability = CapabilityRouter.shared
        let hw = capability.currentCapability
        let aneTOPS = String(format: "%.1f", hw.neuralEngineTOPS)
        DiverLogger.pipeline.info("🧠 [FastVLM] Model resolution — chip: \(hw.chipFamily), RAM: \(hw.physicalMemoryGB)GB, ANE: \(aneTOPS) TOPS")
        
        // 1. Check if HF Hub has the optimal model cached (UserDefaults flag set after download).
        //    HF Hub caches models in its own directory, not in Application Support.
        if hasOptimalModelCached {
            let repo = optimalHuggingFaceRepo
            DiverLogger.pipeline.info("🧠 [FastVLM] ✅ Resolved via HF Hub cache: \(repo)")
            return repo
        }
        
        // 2. Check Application Support for locally provisioned models (e.g., from EdgeDaemon).
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Models/FastVLM")
        
        if let dir = modelsDir {
            if capability.canRunHeavyVLM {
                let config7B = dir.appendingPathComponent("7B/config.json").path
                if FileManager.default.fileExists(atPath: config7B) {
                    DiverLogger.pipeline.info("🧠 [FastVLM] ✅ Resolved: apple/FastVLM/7B (heavy tier, \(hw.physicalMemoryGB)GB RAM)")
                    return "apple/FastVLM/7B"
                }
            }
            if capability.canRunMediumVLM {
                let config15B = dir.appendingPathComponent("1.5B/config.json").path
                if FileManager.default.fileExists(atPath: config15B) {
                    DiverLogger.pipeline.info("🧠 [FastVLM] ✅ Resolved: apple/FastVLM/1.5B (medium tier, \(hw.chipFamily) \(hw.physicalMemoryGB)GB)")
                    return "apple/FastVLM/1.5B"
                }
            }
            if capability.canRunLightVLM {
                let config05B = dir.appendingPathComponent("0.5B/config.json").path
                if FileManager.default.fileExists(atPath: config05B) {
                    DiverLogger.pipeline.info("🧠 [FastVLM] ✅ Resolved: apple/FastVLM/0.5B (light tier, \(hw.physicalMemoryGB)GB RAM)")
                    return "apple/FastVLM/0.5B"
                }
            }
        }
        
        // 3. No cached model — will need to download from HF Hub.
        let fallback = optimalHuggingFaceRepo
        DiverLogger.pipeline.info("🧠 [FastVLM] No local weights cached — will download from HF Hub: \(fallback)")
        return fallback
    }
    
    // MARK: - HuggingFace Repo Mapping (MLX-format weights)
    
    /// Maps hardware capability to the best MLX-format HuggingFace repo.
    /// These are pre-converted MLX checkpoints — no PyTorch→MLX conversion needed at runtime.
    public static var optimalHuggingFaceRepo: String {
        let capability = CapabilityRouter.shared
        if capability.canRunHeavyVLM { return "mlx-community/FastVLM-7B-bf16" }
        if capability.canRunMediumVLM { return "apple/FastVLM-1.5B-int8" }
        return "mlx-community/FastVLM-0.5B-bf16"
    }
    
    /// Whether the optimal model for this device is already cached locally.
    /// Uses a UserDefaults flag set after successful download — the HF Hub
    /// caches models in its own directory, not in Application Support.
    public static var hasOptimalModelCached: Bool {
        let key = "FastVLM.cachedRepo.\(optimalHuggingFaceRepo)"
        return UserDefaults.standard.bool(forKey: key)
    }
    
    /// Mark the optimal model as cached after successful download.
    private static func markModelCached() {
        let key = "FastVLM.cachedRepo.\(optimalHuggingFaceRepo)"
        UserDefaults.standard.set(true, forKey: key)
        invalidateModelIDCache()
        DiverLogger.pipeline.info("✅ [FastVLM] Marked model as cached: \(optimalHuggingFaceRepo)")
    }
    
    /// Downloads the optimal model tier for this device's hardware in the background.
    /// Safe to call at app launch — no-ops if the optimal model is already cached.
    /// - Parameter progress: Callback with download progress (0.0 to 1.0)
    public func downloadOptimalModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        let hw = CapabilityRouter.shared.currentCapability
        DiverLogger.pipeline.info("📥 [FastVLM] Download check — chip: \(hw.chipFamily), RAM: \(hw.physicalMemoryGB)GB, optimal: \(Self.optimalHuggingFaceRepo)")
        
        guard !Self.hasOptimalModelCached else {
            DiverLogger.pipeline.info("✅ [FastVLM] Optimal model already cached — no download needed")
            progress(1.0)
            return
        }
        
        #if canImport(MLXVLM) && !targetEnvironment(simulator)
        let repo = Self.optimalHuggingFaceRepo
        DiverLogger.pipeline.info("📥 [FastVLM] Starting background download: \(repo) for \(hw.chipFamily) (\(hw.physicalMemoryGB)GB)")
        
        let config = ModelConfiguration(id: repo)
        let startTime = Date()
        
        // Patch empty vision_config if already downloaded (e.g. loadModel after download)
        Self.patchVisionConfigIfNeeded(modelID: repo)
        
        // VLMModelFactory downloads from HF Hub and caches locally.
        // First attempt may fail if config.json ships with empty vision_config (mlx-swift-lm bug).
        // If so, patch the cached config and retry.
        do {
            _ = try await VLMModelFactory.shared.loadContainer(
                configuration: config
            ) { update in
                let pct = update.fractionCompleted * 100
                Task { @MainActor in
                    progress(update.fractionCompleted)
                }
                let pctInt = Int(pct)
                if pctInt % 10 == 0 {
                    let pctStr = String(format: "%.0f%%", pct)
                    DiverLogger.pipeline.info("📥 [FastVLM] Download progress: \(pctStr) — \(repo)")
                }
            }
        } catch {
            // Check if this is the empty vision_config bug
            let errorDesc = String(describing: error)
            if errorDesc.contains("cls_ratio") || errorDesc.contains("vision_config") {
                DiverLogger.pipeline.info("🔧 [FastVLM] Config decoding failed — patching vision_config and retrying")
                Self.patchVisionConfigIfNeeded(modelID: repo)
                _ = try await VLMModelFactory.shared.loadContainer(
                    configuration: config
                )
            } else {
                throw error
            }
        }
        
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        DiverLogger.pipeline.info("✅ [FastVLM] Download complete: \(repo) in \(elapsed)s")
        Self.markModelCached()
        #else
        DiverLogger.pipeline.warning("⚠️ [FastVLM] MLXVLM not available on this platform — cannot download")
        throw FastVLMError.notSupported
        #endif
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
        
        // Patch empty vision_config in HF Hub cache before loading (mlx-swift-lm bug workaround)
        Self.patchVisionConfigIfNeeded(modelID: Self.modelID)
        
        let config: ModelConfiguration
        if Self.modelID.starts(with: "apple/FastVLM/") {
            config = ModelConfiguration(
                directory: Self.modelCacheDirectory
            )
        } else {
            config = ModelConfiguration(id: Self.modelID)
        }
        
        do {
            self.container = try await VLMModelFactory.shared.loadContainer(
                configuration: config
            )
        } catch {
            let errorDesc = String(describing: error)
            if errorDesc.contains("cls_ratio") || errorDesc.contains("vision_config") {
                print("🔧 [FastVLMService] Config decoding failed — patching vision_config and retrying")
                Self.patchVisionConfigIfNeeded(modelID: Self.modelID)
                self.container = try await VLMModelFactory.shared.loadContainer(
                    configuration: config
                )
            } else {
                throw error
            }
        }
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
        
        // Patch if already cached; catch-patch-retry handles first-download case
        Self.patchVisionConfigIfNeeded(modelID: Self.modelID)
        
        do {
            self.container = try await VLMModelFactory.shared.loadContainer(
                configuration: config
            ) { update in
                Task { @MainActor in
                    progress(update.fractionCompleted)
                }
            }
        } catch {
            let errorDesc = String(describing: error)
            if errorDesc.contains("cls_ratio") || errorDesc.contains("vision_config") {
                print("🔧 [FastVLMService] Config decoding failed — patching vision_config and retrying")
                Self.patchVisionConfigIfNeeded(modelID: Self.modelID)
                self.container = try await VLMModelFactory.shared.loadContainer(
                    configuration: config
                )
            } else {
                throw error
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
    
    // MARK: - Config Patching
    
    /// Patches `config.json` for models that ship with an empty `vision_config: {}`.
    /// mlx-swift-lm v2.30.x maps `llava_qwen2` → `FastVLMConfiguration` which requires
    /// non-optional fields (`cls_ratio`, `embed_dims`, etc.) in `vision_config`.
    /// The `apple/FastVLM-1.5B-int8` model omits these — this method injects the correct
    /// MobileCLIP-L (1024-dim) encoder config (same values as the working 0.5B model).
    private static func patchVisionConfigIfNeeded(modelID: String) {
        // Only patch HF Hub models (not local edge-downloaded models)
        guard !modelID.starts(with: "apple/FastVLM/") else { return }
        
        // MLXLMCommon.ModelFactory uses cachesDirectory as HubApi downloadBase:
        //   HubApi(downloadBase: .cachesDirectory)
        //   Then localRepoLocation = downloadBase/models/{repo.id}/
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        
        // Try multiple path construction strategies since URL.appending(component:) vs appendingPathComponent
        // behave differently with slashes in the model ID
        let candidates = [
            // Strategy 1: appendingPathComponent treats slash as path separator → .../models/apple/FastVLM-1.5B-int8/
            cachesDir.appendingPathComponent("huggingface/models/\(modelID)/config.json"),
            // Strategy 2: appending(component:) treats entire ID as single component
            cachesDir.appending(component: "huggingface").appending(component: "models").appending(component: modelID).appending(path: "config.json"),
        ]
        
        for configURL in candidates {
            print("🔧 [FastVLM] Checking config at: \(configURL.path)")
            if FileManager.default.fileExists(atPath: configURL.path) {
                patchConfigFile(at: configURL, modelID: modelID)
                return
            }
        }
        
        // Fallback: scan for config.json under caches/huggingface/
        print("⚠️ [FastVLM] Config not found at expected paths, scanning caches...")
        let hfDir = cachesDir.appendingPathComponent("huggingface")
        if let enumerator = FileManager.default.enumerator(atPath: hfDir.path) {
            while let file = enumerator.nextObject() as? String {
                if file.hasSuffix("config.json") && file.lowercased().contains("fastvlm") {
                    let foundURL = hfDir.appendingPathComponent(file)
                    print("🔍 [FastVLM] Found config at: \(foundURL.path)")
                    patchConfigFile(at: foundURL, modelID: modelID)
                    return
                }
            }
        }
        print("⚠️ [FastVLM] No config.json found for \(modelID)")
    }
    
    private static func patchConfigFile(at configURL: URL, modelID: String) {
        
        do {
            let data = try Data(contentsOf: configURL)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            // Check if vision_config exists and is empty
            guard let visionConfig = json["vision_config"] as? [String: Any],
                  visionConfig.isEmpty else {
                return // Already has vision config — no patch needed
            }
            
            print("🔧 [FastVLM] Patching empty vision_config in \(modelID) config.json")
            
            // MobileCLIP-L 1024-dim encoder config (matches mlx-community/FastVLM-0.5B-bf16)
            let patchedVisionConfig: [String: Any] = [
                "cls_ratio": 2.0,
                "down_patch_size": 7,
                "down_stride": 2,
                "downsamples": [true, true, true, true, true],
                "embed_dims": [96, 192, 384, 768, 1536],
                "hidden_size": 1024,
                "image_size": 1024,
                "intermediate_size": 3072,
                "layer_scale_init_value": 1e-05,
                "layers": [2, 12, 24, 4, 2],
                "mlp_ratios": [4, 4, 4, 4, 4],
                "num_classes": 1000,
                "patch_size": 64,
                "pos_embs_shapes": [
                    NSNull(), NSNull(), NSNull(),
                    [7, 7],
                    [3, 3]
                ],
                "projection_dim": 3072,
                "repmixer_kernel_size": 3,
                "token_mixers": ["repmixer", "repmixer", "repmixer", "attention", "attention"]
            ]
            
            json["vision_config"] = patchedVisionConfig
            
            let patched = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try patched.write(to: configURL)
            
            print("✅ [FastVLM] Patched vision_config for \(modelID)")
        } catch {
            print("⚠️ [FastVLM] Failed to patch config.json: \(error)")
        }
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
