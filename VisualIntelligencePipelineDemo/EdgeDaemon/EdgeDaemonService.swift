//
//  EdgeDaemonService.swift
//  EdgeDaemon
//
//  Core service that manages Bonjour advertising, NWListener for incoming
//  connections, and routes distributed actor calls to local ML services.
//  Runs the mac as an edge node for iOS clients.
//

import Foundation
import Network
import Observation
import ImageIO
import DiverKit
import DiverShared

/// Edge daemon status.
enum DaemonStatus: String, Sendable {
    case idle = "Idle"
    case starting = "Starting…"
    case listening = "Listening"
    case processing = "Processing"
    case error = "Error"
}

/// Core edge daemon service managing Bonjour advertising and request routing.
@MainActor
@Observable
final class EdgeDaemonService {
    
    // MARK: - Published State
    
    var status: DaemonStatus = .idle {
        didSet {
            print("🚀 Status: \(status.rawValue)")
        }
    }
    var isListening = false
    var connectedClients: [String] = [] {
        didSet {
            print("👥 Connected clients: \(connectedClients.count)")
        }
    }
    var totalRequests: Int = 0 {
        didSet {
            print("📊 Total requests processed: \(totalRequests)")
        }
    }
    var loadedModels: [String] = []
    var autoStart = false
    var maxConcurrentRequests = 4
    
    // MARK: - Private
    
    private var listener: NWListener?
    private let serviceType = "_visualintel._tcp"
    private let port: UInt16 = 8847
    
    // MARK: - Status Icon
    
    var statusIcon: String {
        switch status {
        case .idle: return "circle"
        case .starting: return "circle.dashed"
        case .listening: return "circle.fill"
        case .processing: return "bolt.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
    
    // MARK: - Lifecycle
    
    init() {
        // Auto-discover available models
        loadedModels = discoverModels()
        
        if autoStart {
            startListening()
        }
    }
    
    func startListening() {
        guard !isListening else { return }
        status = .starting
        
        do {
            // TLS 1.3 parameters
            let params = NWParameters.tls
            params.includePeerToPeer = true
            
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            // Advertise via Bonjour with TXT record metadata
            var txtRecord = NWTXTRecord()
            txtRecord["chip"] = chipFamily()
            txtRecord["tops"] = String(format: "%.0f", neuralEngineTOPS())
            txtRecord["models"] = loadedModels.joined(separator: ",")
            
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac Edge Node",
                type: serviceType,
                txtRecord: txtRecord
            )
            
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
            
            print("🟢 EdgeDaemon: Starting on port \(port)")
        } catch {
            status = .error
            print("⚠️ EdgeDaemon: Failed to start: \(error)")
        }
    }
    
    func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
        status = .idle
        connectedClients.removeAll()
        print("🔴 EdgeDaemon: Stopped")
    }
    
    // MARK: - Connection Handling
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            status = .listening
            print("🟢 EdgeDaemon: Listening on port \(port)")
        case .failed(let error):
            status = .error
            isListening = false
            print("⚠️ EdgeDaemon: Listener failed: \(error)")
        case .cancelled:
            isListening = false
            status = .idle
        default:
            break
        }
    }
    
    nonisolated private func handleNewConnection(_ connection: NWConnection) {
        let clientName = connection.endpoint.debugDescription
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.connectedClients.append(clientName)
                    print("🔗 EdgeDaemon: Client connected: \(clientName)")
                case .cancelled, .failed:
                    self?.connectedClients.removeAll { $0 == clientName }
                    print("🔗 EdgeDaemon: Client disconnected: \(clientName)")
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
        receiveMessages(on: connection)
    }
    
    nonisolated private func receiveMessages(on connection: NWConnection) {
        // Read length-prefixed frames (matching NWTransportLayer protocol)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, _, error in
            guard let self, let header = content, header.count == 4, error == nil else { return }
            
            let frameLength = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            guard frameLength < 50_000_000 else { return } // 50MB limit
            
            connection.receive(
                minimumIncompleteLength: Int(frameLength),
                maximumLength: Int(frameLength)
            ) { [weak self] body, _, _, error in
                guard let self, let body, error == nil else { return }
                
                Task { @MainActor in
                    self.totalRequests += 1
                    self.status = .processing
                }
                
                // Process the request and send response
                Task {
                    let response = await self.processRequest(body)
                    
                    // Send response with length prefix
                    var responseLength = UInt32(response.count).bigEndian
                    var frame = Data(bytes: &responseLength, count: 4)
                    frame.append(response)
                    
                    connection.send(content: frame, completion: .contentProcessed { _ in })
                    
                    await MainActor.run {
                        self.status = .listening
                    }
                }
                
                // Continue receiving
                self.receiveMessages(on: connection)
            }
        }
    }
    
    // MARK: - Request Processing
    
    /// Request envelope sent by iOS clients.
    private struct EdgeRequest: Codable {
        let method: String      // "vision", "vlm", "nowcast", "gov", "commerce"
        let payload: Data       // Method-specific payload (image data, JSON params, etc.)
    }
    
    /// Response envelope sent back to iOS clients.
    private struct EdgeResponse: Codable {
        let method: String
        let result: Data   // JSON-encoded result type (VisionAnalysisResult, etc.)
        let node: String
    }
    
    nonisolated private func processRequest(_ data: Data) async -> Data {
        // Parse the request envelope
        guard let request = try? JSONDecoder().decode(EdgeRequest.self, from: data) else {
            // Legacy format: target + payload (length-prefixed)
            return await processLegacyRequest(data)
        }
        
        let nodeName = Host.current().localizedName ?? "Edge Node"
        
        print("📡 EdgeDaemon: Processing \(request.method) (\(request.payload.count) bytes)")
        
        do {
            let resultData: Data
            
            switch request.method {
            case "vision":
                // Run the same IntelligenceProcessor pipeline as iOS
                let processor = IntelligenceProcessor()
                guard let source = CGImageSourceCreateWithData(request.payload as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw EdgeInferenceError.invalidImageData
                }
                
                let results = try await processor.process(image: cgImage, mode: .fullAnalysis)
                let visionResult = convertToVisionResult(results)
                resultData = try JSONEncoder().encode(visionResult)
                
            case "vlm":
                // Run FastVLM — same service as iOS, potentially larger model
                guard let source = CGImageSourceCreateWithData(request.payload as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw EdgeInferenceError.invalidImageData
                }
                
                let processor = IntelligenceProcessor()
                let visionResults = try await processor.process(image: cgImage, mode: .fullAnalysis)
                let visionResult = convertToVisionResult(visionResults)
                
                let vlmService = FastVLMEnrichmentService()
                let analysis = try await vlmService.analyze(
                    image: cgImage,
                    visionTags: visionResult.semanticTags,
                    enrichmentContext: "",
                    transcription: visionResult.ocrText
                )
                
                let llmResult = LLMAnalysisResult(
                    summary: analysis?.contextSummary,
                    statements: analysis?.statements ?? [],
                    purpose: analysis?.suggestedPurpose,
                    tags: analysis?.suggestedTags ?? [],
                    imageDescription: analysis?.imageDescription
                )
                resultData = try JSONEncoder().encode(llmResult)
                
            case "nowcast":
                // Run NowcastingEngine with real pricing data
                let params = try JSONDecoder().decode(NowcastRequest.self, from: request.payload)
                let pricingService = PricingDataService()
                let engine = NowcastingEngine()
                
                let worldBank: [PriceDataPoint] = await pricingService.fetchWorldBankPrices(commodityID: params.commodityID)
                let bls: [PriceDataPoint] = await pricingService.fetchBLSPPI(seriesID: params.commodityID)
                let series: [[PriceDataPoint]] = [worldBank, bls].filter { !$0.isEmpty }
                let nowcast = engine.nowcast(series: series, horizonDays: params.horizonDays)
                
                let allPoints = (worldBank + bls).sorted(by: { $0.date < $1.date })
                let trajectory = PriceTrajectory(
                    commodityID: params.commodityID,
                    dataPoints: allPoints,
                    projectedDirection: nowcast.direction,
                    confidenceInterval: nowcast.confidence,  // NowcastResult.confidence
                    horizonDays: params.horizonDays
                )
                resultData = try JSONEncoder().encode(trajectory)
                
            case "gov":
                // Run GovernmentDataService — same 4 parallel API calls as iOS
                let product = try JSONDecoder().decode(ProductClassification.self, from: request.payload)
                let service = GovernmentDataService()
                let enrichment = await service.enrich(product: product)
                resultData = try JSONEncoder().encode(enrichment)
                
            case "commerce":
                // Run AffiliateRoutingService — same platform ranking as iOS
                let params = try JSONDecoder().decode(CommerceRequest.self, from: request.payload)
                let router = AffiliateRoutingService()
                let platforms = try await router.rankPlatforms(for: params.product, policy: params.policy)
                resultData = try JSONEncoder().encode(platforms)
                
            default:
                print("⚠️ EdgeDaemon: Unknown method: \(request.method)")
                resultData = Data()
            }
            
            let response = EdgeResponse(method: request.method, result: resultData, node: nodeName)
            return try JSONEncoder().encode(response)
            
        } catch {
            print("⚠️ EdgeDaemon: Error processing \(request.method): \(error)")
            let errorResponse: [String: String] = [
                "error": error.localizedDescription,
                "method": request.method,
                "node": nodeName
            ]
            return (try? JSONEncoder().encode(errorResponse)) ?? Data()
        }
    }
    
    /// Legacy frame format fallback: [4-byte target length][target string][payload]
    nonisolated private func processLegacyRequest(_ data: Data) async -> Data {
        guard data.count >= 4 else { return Data() }
        
        let targetLength = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let targetData = data.dropFirst(4).prefix(Int(targetLength))
        let payload = Data(data.dropFirst(4 + Int(targetLength)))
        
        let target = String(data: targetData, encoding: .utf8) ?? ""
        
        // Map legacy target strings to the new method-based dispatch
        let request = EdgeRequest(method: target, payload: payload)
        let requestData = (try? JSONEncoder().encode(request)) ?? Data()
        return await processRequest(requestData)
    }
    
    /// Convert [IntelligenceResult] → VisionAnalysisResult for network transport.
    nonisolated private func convertToVisionResult(_ results: [IntelligenceResult]) -> VisionAnalysisResult {
        var ocrText: String? = nil
        var qrURLs: [String] = []
        var semanticTags: [String] = []
        var hasDocument = false
        var hasForegroundSubject = false
        var aestheticsScore: Float? = nil
        var saliencyMap: SaliencyResult? = nil
        
        for result in results {
            switch result {
            case .text(let text, _):
                ocrText = (ocrText ?? "") + text + "\n"
            case .qr(let url):
                qrURLs.append(url.absoluteString)
            case .semantic(let tag, _):
                semanticTags.append(tag)
            case .document:
                hasDocument = true
            case .siftedSubject:
                hasForegroundSubject = true
            case .aesthetics(let score):
                aestheticsScore = score
            case .saliency(let saliency):
                saliencyMap = saliency
            default:
                break
            }
        }
        
        return VisionAnalysisResult(
            ocrText: ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
            qrURLs: qrURLs,
            semanticTags: semanticTags,
            hasDocument: hasDocument,
            hasForegroundSubject: hasForegroundSubject,
            aestheticsScore: aestheticsScore,
            saliencyMap: saliencyMap
        )
    }
    
    // MARK: - Request Parameter Types
    
    private struct NowcastRequest: Codable {
        let commodityID: String
        let horizonDays: Int
    }
    
    private struct CommerceRequest: Codable {
        let product: ProductClassification
        let policy: EthicalPolicy
    }
    
    // MARK: - System Info
    
    nonisolated private func chipFamily() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)
        
        if brandString.contains("M4") { return "M4" }
        if brandString.contains("M3") { return "M3" }
        if brandString.contains("M2") { return "M2" }
        if brandString.contains("M1") { return "M1" }
        return "Apple Silicon"
    }
    
    nonisolated private func neuralEngineTOPS() -> Float {
        let chip = chipFamily()
        switch chip {
        case "M4": return 38.0
        case "M3": return 18.0
        case "M2": return 15.8
        case "M1": return 11.0
        default: return 11.0
        }
    }
    
    // MARK: - Model Download
    
    nonisolated func downloadModel(name: String) async {
        let fastVLMTiers = [
            ("FastVLM/0.5B", "fastvlm-0.5b"),
            ("FastVLM/1.5B", "fastvlm-1.5b"),
            ("FastVLM/3B", "fastvlm-3b"),
        ]
        
        guard let match = fastVLMTiers.first(where: { $0.1 == name }) else {
            print("⚠️ EdgeDaemon: Model '\(name)' not found. Available models: fastvlm-0.5b, fastvlm-1.5b, fastvlm-3b")
            return
        }
        
        let path = match.0
        
        print("⏳ Downloading model: \(name) (~1.5GB) ...")
        
        do {
            let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!.appendingPathComponent("Models")
            let targetDir = modelsDir.appendingPathComponent(path)
            
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            
            let configURL = URL(string: "https://huggingface.co/apple/\(path)/resolve/main/config.json")!
            let (downloadURL, response) = try await URLSession.shared.download(from: configURL)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("⚠️ EdgeDaemon: Download failed (server error).")
                return
            }
            
            let configDest = targetDir.appendingPathComponent("config.json")
            try? FileManager.default.removeItem(at: configDest)
            try FileManager.default.moveItem(at: downloadURL, to: configDest)
            
            print("✅ EdgeDaemon: Successfully downloaded \(name) to \(targetDir.path)")
            
            // Re-discover models and update loadedModels array
            let newlyDiscovered = discoverModels()
            await MainActor.run {
                self.loadedModels = newlyDiscovered
            }
            
        } catch {
            print("⚠️ EdgeDaemon: Download failed: \(error.localizedDescription)")
        }
    }
    
    nonisolated private func discoverModels() -> [String] {
        var models = ["vision-pipeline"]
        
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Models")
        
        guard let dir = modelsDir else { return models }
        
        // Check for each FastVLM tier
        let fastVLMTiers = [
            ("FastVLM/0.5B", "fastvlm-0.5b"),
            ("FastVLM/1.5B", "fastvlm-1.5b"),
            ("FastVLM/3B", "fastvlm-3b"),
        ]
        
        for (path, modelID) in fastVLMTiers {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(path).path) {
                models.append(modelID)
            }
        }
        
        // Check for YOLO CoreML model
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("YOLOv8.mlmodelc").path) {
            models.append("yolov8-coreml")
        }
        
        return models
    }
}
