//
//  CLaRaLatentService.swift
//  DiverKit
//
//  Wraps Apple's CLaRa 7B model using pure MLX Swift for agentic search locally on iOS/macOS.
//  Downloads the optimal model tier from HuggingFace Hub based on device hardware.
//

import Foundation
import SwiftData
import DiverShared
import os

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

/// A native MLX Swift service that loads the CLaRa model locally
/// and performs text generation/RAG querying.
///
/// Model tiers (resolved by device capability):
/// - **7B** (≥16GB RAM): Full CLaRa-7B-Instruct — best quality
/// - **3B** (≥8GB M-series): Smaller instruct model — good quality, lower memory
/// - **Fallback**: Returns nil (model not available on constrained devices)
public final class CLaRaLatentService: LocalAgenticSearching, @unchecked Sendable {
    
    public static let shared = CLaRaLatentService()
    
    // MARK: - Model Availability
    
    public var isAvailable: Bool {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        let capability = CapabilityRouter.shared
        guard capability.canRunLightVLM else {
            DiverLogger.pipeline.debug("🧩 [CLaRa] Not available — device has <8GB RAM")
            return false
        }
        return true
        #else
        return false
        #endif
    }
    
    /// Whether the optimal CLaRa model for this device is already cached locally.
    /// Checks both the App Support manual-install path AND the MLXLLM Hub cache.
    public var hasModelCached: Bool {
        if FileManager.default.fileExists(atPath: Self.modelCacheDirectory.path) { return true }
        // Also check the MLXLLM Hub cache (~/Library/Caches/models/<repo>)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("models/\(Self.optimalHuggingFaceRepo)")
        if let cache = cacheDir, FileManager.default.fileExists(atPath: cache.appendingPathComponent("config.json").path) {
            return true
        }
        return false
    }
    
    /// Key to track repos that failed download (PyTorch format, missing config.json, etc.)
    private static let downloadFailedKey = "clara_download_failed_repo"
    
    // MARK: - Model Resolution
    
    /// Local cache directory for CLaRa weights.
    private static var modelCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Models/CLaRa")
    }
    
    /// Maps device hardware to the optimal HuggingFace repo.
    /// The CLaRa model is hosted at apple/CLaRa-7B-Instruct (no MLX-community port).
    /// On macOS, EdgeModelProvisioner fuses the LoRA adapter locally into MLX format.
    /// On iOS, the model is downloaded from HF Hub and loaded via MLXLLM.
    public static var optimalHuggingFaceRepo: String {
        DiverLogger.pipeline.info("🧩 [CLaRa] Optimal tier: 7B-Instruct")
        return "apple/CLaRa-7B-Instruct"
    }
    
    /// Returns the HuggingFace repo if the model should be downloaded from Hub,
    /// or nil if the model is already available locally.
    private static var resolvedHuggingFaceRepo: String? {
        if FileManager.default.fileExists(atPath: modelCacheDirectory.path) {
            return nil // Already have local weights
        }
        return optimalHuggingFaceRepo
    }
    
    // MARK: - Model Download
    
    /// Downloads the optimal CLaRa model tier for this device in the background.
    /// Safe to call at app launch — no-ops if the model is already cached.
    /// - Parameter progress: Callback with download progress (0.0 to 1.0)
    public func downloadModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        let hw = CapabilityRouter.shared.currentCapability
        DiverLogger.pipeline.info("📥 [CLaRa] Download check — chip: \(hw.chipFamily), RAM: \(hw.physicalMemoryGB)GB")
        
        // apple/CLaRa-7B-Instruct is PyTorch format — MLXLLM can't load it directly.
        // On iOS/iPadOS, CLaRa runs via the macOS EdgeDaemon (which converts PyTorch→MLX).
        // Only attempt download on macOS where we have the full provisioning pipeline.
        #if !os(macOS)
        DiverLogger.pipeline.info("⏭️ [CLaRa] Skipping on-device download — PyTorch model requires macOS EdgeDaemon for MLX conversion. Use edge node instead.")
        return
        #endif
        
        guard !hasModelCached else {
            DiverLogger.pipeline.info("✅ [CLaRa] Model already cached")
            progress(1.0)
            return
        }
        
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        let repo = Self.optimalHuggingFaceRepo
        DiverLogger.pipeline.info("📥 [CLaRa] Starting background download: \(repo) for \(hw.chipFamily) (\(hw.physicalMemoryGB)GB)")
        
        let config = MLXLMCommon.ModelConfiguration(id: repo)
        let startTime = Date()
        
        // LLMModelFactory downloads from HF Hub and caches locally
        _ = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { update in
            let pct = update.fractionCompleted * 100
            Task { @MainActor in
                progress(update.fractionCompleted)
            }
            let pctInt = Int(pct)
            if pctInt % 10 == 0 {
                let pctStr = String(format: "%.0f%%", pct)
                DiverLogger.pipeline.info("📥 [CLaRa] Download progress: \(pctStr) — \(repo)")
            }
        }
        
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        // Clear any previous failure marker on success
        UserDefaults.standard.removeObject(forKey: Self.downloadFailedKey)
        DiverLogger.pipeline.info("✅ [CLaRa] Download complete: \(repo) in \(elapsed)s")
        #else
        DiverLogger.pipeline.warning("⚠️ [CLaRa] MLXLLM not available on this platform — cannot download")
        throw CLaRaError.notSupported
        #endif
    }
    
    // MARK: - Model Loading
    
    #if canImport(MLXLLM) && !targetEnvironment(simulator)
    private var container: MLXLMCommon.ModelContainer?
    private let loadLock = NSLock()
    #endif
    
    private var isLoading = false
    
    // MARK: - Persistent Document Store (RAG Index)
    
    /// A chunk of document text indexed for retrieval.
    private struct DocumentChunk: Sendable, Codable {
        let documentID: String
        let text: String
        let terms: Set<String>           // Lowercased, whitespace-split tokens
        let metadata: [String: String]
    }
    
    /// Thread-safe document index — loaded from disk cache on first access.
    /// Documents are chunked at ingestion and matched by term overlap at query time.
    private var documentIndex: [DocumentChunk] = []
    private let indexLock = NSLock()
    private var indexLoaded = false
    private var pendingSaveTask: Task<Void, Never>?
    
    /// File URL for the persisted index cache.
    private static var indexCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CLaRa")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("document_index.json.gz")
    }
    
    /// Load the cached index from disk if not already loaded.
    private func loadCachedIndexIfNeeded() {
        guard !indexLoaded else { return }
        indexLoaded = true
        
        let url = Self.indexCacheURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            DiverLogger.pipeline.info("🧩 [CLaRa] No cached index found — will build from scratch")
            return
        }
        
        do {
            let compressed = try Data(contentsOf: url)
            let data: Data
            if let decompressed = try? (compressed as NSData).decompressed(using: .zlib) as Data {
                data = decompressed
            } else {
                data = compressed // Fallback: maybe it's uncompressed
            }
            let chunks = try JSONDecoder().decode([DocumentChunk].self, from: data)
            documentIndex = chunks
            DiverLogger.pipeline.info("🧩 [CLaRa] Loaded cached index: \(chunks.count) chunks from disk")
        } catch {
            DiverLogger.pipeline.error("⚠️ [CLaRa] Failed to load cached index: \(error) — will rebuild")
        }
    }
    
    /// Save the current index to disk (debounced to avoid rapid writes during bulk ingestion).
    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveIndexToDisk()
        }
    }
    
    /// Write the index to disk as compressed JSON.
    private func saveIndexToDisk() {
        indexLock.lock()
        let snapshot = documentIndex
        indexLock.unlock()
        
        do {
            let data = try JSONEncoder().encode(snapshot)
            let compressed = try (data as NSData).compressed(using: .zlib) as Data
            try compressed.write(to: Self.indexCacheURL, options: .atomic)
            DiverLogger.pipeline.debug("🧩 [CLaRa] Saved index to disk: \(snapshot.count) chunks (\(compressed.count / 1024)KB)")
        } catch {
            DiverLogger.pipeline.error("⚠️ [CLaRa] Failed to save index: \(error)")
        }
    }
    
    /// Number of document chunks currently indexed.
    public var documentCount: Int {
        indexLock.lock()
        defer { indexLock.unlock() }
        loadCachedIndexIfNeeded()
        return documentIndex.count
    }
    
    /// Ingest a document into the RAG index.
    /// Splits text into overlapping chunks and indexes terms for retrieval.
    /// Persists to disk after a debounced delay.
    /// - Parameters:
    ///   - id: Unique document/item identifier
    ///   - text: Full document text
    ///   - metadata: Optional metadata (title, category, etc.)
    /// - Returns: Number of chunks created
    @discardableResult
    public func ingest(id: String, text: String, metadata: [String: String] = [:]) -> Int {
        let chunks = Self.chunkText(text, chunkSize: 512, overlap: 64)
        
        indexLock.lock()
        loadCachedIndexIfNeeded()
        // Remove any existing chunks for this document (re-ingestion)
        documentIndex.removeAll { $0.documentID == id }
        
        let newChunks = chunks.map { chunk in
            DocumentChunk(
                documentID: id,
                text: chunk,
                terms: Self.tokenize(chunk),
                metadata: metadata
            )
        }
        documentIndex.append(contentsOf: newChunks)
        indexLock.unlock()
        
        scheduleSave()
        
        DiverLogger.pipeline.info("🧩 [CLaRa] Ingested document \(id): \(newChunks.count) chunks, index total: \(self.documentCount)")
        return newChunks.count
    }
    
    /// Retrieve the most relevant document chunks for a query (BM25-style term overlap).
    /// - Parameters:
    ///   - query: Natural language query
    ///   - topK: Maximum number of chunks to return
    /// - Returns: Ranked list of (text, documentID, score) tuples
    public func retrieveContext(for query: String, topK: Int = 100) -> [(text: String, documentID: String, score: Double)] {
        let queryTerms = Self.tokenize(query)
        guard !queryTerms.isEmpty else { return [] }
        
        indexLock.lock()
        loadCachedIndexIfNeeded()
        let index = documentIndex
        indexLock.unlock()
        
        guard !index.isEmpty else {
            DiverLogger.pipeline.debug("🧩 [CLaRa] No documents indexed — returning empty context")
            return []
        }
        
        // Score each chunk by term overlap (Jaccard-like)
        let scored = index.map { chunk -> (chunk: DocumentChunk, score: Double) in
            let intersection = queryTerms.intersection(chunk.terms)
            let union = queryTerms.union(chunk.terms)
            let score = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
            return (chunk, score)
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        .prefix(topK)
        
        let results = scored.map { (text: $0.chunk.text, documentID: $0.chunk.documentID, score: $0.score) }
        DiverLogger.pipeline.info("🧩 [CLaRa] Retrieved \(results.count) chunks for query (index size: \(index.count))")
        return results
    }
    
    /// Remove a single document from the index by ID.
    /// Call when a ProcessedItem is deleted.
    /// - Returns: Number of chunks removed
    @discardableResult
    public func removeDocument(id: String) -> Int {
        indexLock.lock()
        loadCachedIndexIfNeeded()
        let before = documentIndex.count
        documentIndex.removeAll { $0.documentID == id }
        let removed = before - documentIndex.count
        indexLock.unlock()
        
        if removed > 0 {
            scheduleSave()
            DiverLogger.pipeline.info("🧩 [CLaRa] Removed document \(id): \(removed) chunks, index total: \(self.documentCount)")
        }
        return removed
    }
    
    /// Clear the entire document index (memory and disk).
    public func clearIndex() {
        indexLock.lock()
        documentIndex.removeAll()
        indexLoaded = true // Mark as loaded so we don't try to read stale file
        indexLock.unlock()
        try? FileManager.default.removeItem(at: Self.indexCacheURL)
        UserDefaults.standard.removeObject(forKey: "CLaRa_lastIndexedAt")
        DiverLogger.pipeline.info("🧹 [CLaRa] Document index cleared (memory + disk)")
    }
    
    // MARK: - Text Chunking Utilities
    
    /// Split text into overlapping chunks for better retrieval granularity.
    private static func chunkText(_ text: String, chunkSize: Int, overlap: Int) -> [String] {
        guard text.count > chunkSize else { return [text] }
        
        var chunks: [String] = []
        var startIndex = text.startIndex
        
        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[startIndex..<endIndex]))
            
            if endIndex == text.endIndex { break }
            startIndex = text.index(endIndex, offsetBy: -overlap, limitedBy: text.startIndex) ?? text.startIndex
        }
        
        return chunks
    }
    
    /// Tokenize text into a set of lowercased terms (simple whitespace + punctuation split).
    private static func tokenize(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }  // Skip short noise words
        return Set(words)
    }
    
    // MARK: - SwiftData Integration
    
    /// Compose a text document from a ProcessedItem's available fields.
    /// This produces the text blob that gets chunked and indexed for retrieval.
    /// Includes both basic text fields AND decoded context data blobs for deep searchability.
    private static func composeDocument(
        id: String,
        title: String?,
        summary: String?,
        transcription: String?,
        tags: [String],
        visualTags: [String],
        categories: [String],
        location: String?,
        purposes: [String],
        productMetadata: String?,
        url: String?,
        // Context data blobs — decoded inline for indexing
        placeContextData: Data? = nil,
        webContextData: Data? = nil,
        weatherContextData: Data? = nil,
        documentContextData: Data? = nil,
        qrContextData: Data? = nil,
        fastVLMAnalysisData: Data? = nil,
        questions: [String] = []
    ) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append("Title: \(title)") }
        if let summary, !summary.isEmpty { parts.append("Summary: \(summary)") }
        if let transcription, !transcription.isEmpty { parts.append("OCR/Transcription: \(transcription)") }
        if !tags.isEmpty { parts.append("Tags: \(tags.joined(separator: ", "))") }
        if !visualTags.isEmpty { parts.append("Visual: \(visualTags.joined(separator: ", "))") }
        if !categories.isEmpty { parts.append("Categories: \(categories.joined(separator: ", "))") }
        if let location, !location.isEmpty { parts.append("Location: \(location)") }
        if !purposes.isEmpty { parts.append("Purposes: \(purposes.joined(separator: ", "))") }
        if let productMetadata, !productMetadata.isEmpty { parts.append("Product: \(productMetadata)") }
        if let url, !url.isEmpty { parts.append("URL: \(url)") }
        if !questions.isEmpty { parts.append("Questions: \(questions.joined(separator: ", "))") }
        
        // Decode and include context data blobs for richer indexing
        let decoder = JSONDecoder()
        
        if let data = placeContextData, let place = try? decoder.decode(PlaceContext.self, from: data) {
            var placeParts: [String] = []
            if let name = place.name { placeParts.append(name) }
            if let addr = place.address { placeParts.append(addr) }
            if !place.categories.isEmpty { placeParts.append(place.categories.joined(separator: ", ")) }
            if !placeParts.isEmpty { parts.append("Place: \(placeParts.joined(separator: ", "))") }
        }
        
        if let data = webContextData, let web = try? decoder.decode(WebContext.self, from: data) {
            var webParts: [String] = []
            if let s = web.siteName { webParts.append(s) }
            if let t = web.textContent { webParts.append(String(t.prefix(500))) }
            if !webParts.isEmpty { parts.append("Web: \(webParts.joined(separator: " — "))") }
        }
        
        if let data = weatherContextData, let weather = try? decoder.decode(WeatherContext.self, from: data) {
            let tempF = weather.temperatureCelsius * 9.0 / 5.0 + 32.0
            parts.append("Weather: \(weather.condition), \(String(format: "%.0f", tempF))°F")
        }
        
        if let data = documentContextData, let doc = try? decoder.decode(DocumentContext.self, from: data) {
            var docParts: [String] = ["Type: \(doc.fileType)"]
            if let author = doc.author { docParts.append("Author: \(author)") }
            parts.append("Document: \(docParts.joined(separator: ", "))")
        }
        
        if let data = qrContextData, let qr = try? decoder.decode(QRCodeContext.self, from: data) {
            parts.append("QR Code: \(qr.payload)")
        }
        
        if let data = fastVLMAnalysisData, let vlm = try? decoder.decode(FastVLMAnalysis.self, from: data) {
            if let desc = vlm.imageDescription, !desc.isEmpty {
                parts.append("Vision Analysis: \(desc)")
            }
            if let summary = vlm.contextSummary, !summary.isEmpty {
                parts.append("Context: \(summary)")
            }
        }
        
        return parts.joined(separator: "\n")
    }
    
    /// Ingest a single ProcessedItem into the document index.
    /// Call this after pipeline processing completes for an item.
    @discardableResult
    public func ingestProcessedItem(
        id: String,
        title: String?,
        summary: String?,
        transcription: String?,
        tags: [String],
        visualTags: [String],
        categories: [String],
        location: String?,
        purposes: [String],
        productMetadata: String?,
        url: String?,
        placeContextData: Data? = nil,
        webContextData: Data? = nil,
        weatherContextData: Data? = nil,
        documentContextData: Data? = nil,
        qrContextData: Data? = nil,
        fastVLMAnalysisData: Data? = nil,
        questions: [String] = []
    ) -> Int {
        let doc = Self.composeDocument(
            id: id, title: title, summary: summary, transcription: transcription,
            tags: tags, visualTags: visualTags, categories: categories,
            location: location, purposes: purposes, productMetadata: productMetadata,
            url: url,
            placeContextData: placeContextData,
            webContextData: webContextData,
            weatherContextData: weatherContextData,
            documentContextData: documentContextData,
            qrContextData: qrContextData,
            fastVLMAnalysisData: fastVLMAnalysisData,
            questions: questions
        )
        guard !doc.isEmpty else { return 0 }
        
        var metadata: [String: String] = [:]
        if let title { metadata["title"] = title }
        if !categories.isEmpty { metadata["category"] = categories.first ?? "" }
        
        return ingest(id: id, text: doc, metadata: metadata)
    }
    
    /// Bulk-populate the document index from ProcessedItems in the SwiftData container.
    /// On first launch, indexes everything. On subsequent launches, only indexes
    /// items updated since the last index run (incremental).
    /// Batched in groups of 50 with async yields to avoid blocking the main-thread
    /// CoreData coordinator with massive WAL checkpoints.
    public func populateIndex(container: SwiftData.ModelContainer) async {
        let context = SwiftData.ModelContext(container)
        context.autosaveEnabled = false
        
        let lastIndexedKey = "CLaRa_lastIndexedAt"
        let lastIndexedAt = UserDefaults.standard.object(forKey: lastIndexedKey) as? Date
        let isIncremental = lastIndexedAt != nil && documentCount > 0
        
        let batchSize = 50
        var offset = 0
        var totalItems = 0
        var totalChunks = 0
        let mode = isIncremental ? "incremental" : "full"
        
        do {
            // First pass: get total count for logging
            var countDescriptor = FetchDescriptor<ProcessedItem>()
            if isIncremental, let since = lastIndexedAt {
                countDescriptor.predicate = #Predicate { item in
                    item.updatedAt > since
                }
            }
            let itemCount = try context.fetchCount(countDescriptor)
            
            guard itemCount > 0 || !isIncremental else {
                DiverLogger.pipeline.info("🧩 [CLaRa] Index up to date — no new items since last run")
                return
            }
            
            DiverLogger.pipeline.info("🧩 [CLaRa] Populating index (\(mode)): \(itemCount) items...")
            
            // Batch fetch and process
            while true {
                var descriptor = FetchDescriptor<ProcessedItem>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                if isIncremental, let since = lastIndexedAt {
                    descriptor.predicate = #Predicate { item in
                        item.updatedAt > since
                    }
                }
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset
                
                let batch = try context.fetch(descriptor)
                if batch.isEmpty { break }
                
                for item in batch {
                    let chunks = ingestProcessedItem(
                        id: item.id,
                        title: item.title,
                        summary: item.summary,
                        transcription: item.transcription,
                        tags: item.tags,
                        visualTags: item.visualTags,
                        categories: item.categories,
                        location: item.location,
                        purposes: item.purposes,
                        productMetadata: item.productMetadata,
                        url: item.url,
                        placeContextData: item.placeContextData,
                        webContextData: item.webContextData,
                        weatherContextData: item.weatherContextData,
                        documentContextData: item.documentContextData,
                        qrContextData: item.qrContextData,
                        fastVLMAnalysisData: item.fastVLMAnalysisData,
                        questions: item.questions
                    )
                    totalChunks += chunks
                }
                
                totalItems += batch.count
                offset += batchSize
                
                // Yield to let the main thread process pending WAL checkpoints
                await Task.yield()
            }
            
            // Persist the high-water mark
            UserDefaults.standard.set(Date(), forKey: lastIndexedKey)
            
            DiverLogger.pipeline.info("✅ [CLaRa] Index populated (\(mode)): \(totalItems) items → \(totalChunks) chunks (total: \(self.documentCount))")
        } catch {
            DiverLogger.pipeline.error("❌ [CLaRa] Failed to populate index: \(error)")
        }
    }
    
    public init() {}


    
    public func loadModel() async throws {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        guard container == nil else {
            DiverLogger.pipeline.debug("🧩 [CLaRa] Model already loaded in memory")
            return
        }
        
        let hw = CapabilityRouter.shared.currentCapability
        DiverLogger.pipeline.info("📦 [CLaRa] Loading model into unified memory — \(hw.chipFamily) (\(hw.physicalMemoryGB)GB)")
        
        let config: MLXLMCommon.ModelConfiguration
        if FileManager.default.fileExists(atPath: Self.modelCacheDirectory.path) {
            // Load from local directory (EdgeDaemon manual install path)
            DiverLogger.pipeline.info("📦 [CLaRa] Source: local directory \(Self.modelCacheDirectory.path)")
            config = MLXLMCommon.ModelConfiguration(directory: Self.modelCacheDirectory)
        } else {
            #if os(macOS)
            // Only macOS can load from HF Hub — EdgeModelProvisioner converts PyTorch→MLX
            let repo = Self.optimalHuggingFaceRepo
            DiverLogger.pipeline.info("📦 [CLaRa] Source: HuggingFace Hub \(repo)")
            config = MLXLMCommon.ModelConfiguration(id: repo)
            #else
            // On iOS/iPadOS, apple/CLaRa-7B-Instruct is PyTorch — can't load via MLXLLM.
            // CLaRa inference happens via the macOS EdgeDaemon over Bonjour.
            DiverLogger.pipeline.info("⏭️ [CLaRa] No local MLX weights on iOS — use edge node for CLaRa inference")
            throw CLaRaError.notSupported
            #endif
        }
        
        let startTime = Date()
        self.container = try await LLMModelFactory.shared.loadContainer(configuration: config)
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        DiverLogger.pipeline.info("✅ [CLaRa] Model loaded in \(elapsed)s")
        #else
        throw CLaRaError.notSupported
        #endif
    }
    
    /// Unload the model from GPU memory to free resources.
    public func unloadModel() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        container = nil
        DiverLogger.pipeline.info("🧹 [CLaRa] Model unloaded from memory")
        #endif
    }
    
    // MARK: - Query
    
    public func query(documentText: String, question: String) async throws -> String? {
        guard isAvailable else { return nil }
        
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        isLoading = true
        defer { isLoading = false }
        
        DiverLogger.pipeline.info("🔍 [CLaRa] Query: \(String(question.prefix(80)))...")
        let queryStart = Date()
        
        return await Task(priority: .userInitiated) { [weak self] () -> String? in
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
                
                let result: String = try await container.perform { context in
                    let lmInput = try await context.processor.prepare(input: UserInput(prompt: prompt))
                    let params = GenerateParameters(maxTokens: 256, temperature: 0.1)
                    
                    let stream = try MLXLMCommon.generate(input: lmInput, parameters: params, context: context)
                    
                    var output = ""
                    for await chunk in stream {
                        switch chunk {
                        case .chunk(let text):
                            output += text
                        default: break
                        }
                    }
                    
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(queryStart))
                DiverLogger.pipeline.info("✅ [CLaRa] Answer generated in \(elapsed)s (\(result.count) chars)")
                return result
            } catch {
                DiverLogger.pipeline.error("❌ [CLaRa] Query failed: \(error)")
                return nil
            }
        }.value
        #else
        return nil
        #endif
    }
    
    // MARK: - Errors
    
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
