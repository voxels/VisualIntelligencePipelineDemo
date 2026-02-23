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
#if os(macOS)
import Darwin
#endif

/// Edge daemon status.
public enum DaemonStatus: String, Sendable {
    case idle = "Idle"
    case starting = "Starting…"
    case listening = "Listening"
    case processing = "Processing"
    case error = "Error"
}

/// Core edge daemon service managing Bonjour advertising and request routing.
@MainActor
@Observable
public final class EdgeDaemonService {
    
    // MARK: - Published State
    
    public var status: DaemonStatus = .idle {
        didSet {
            print("🚀 Status: \(status.rawValue)")
        }
    }
    public var isListening = false
    public var connectedClients: [String] = [] {
        didSet {
            print("👥 Connected clients: \(connectedClients.count)")
        }
    }
    public var totalRequests: Int = 0 {
        didSet {
            print("📊 Total requests processed: \(totalRequests)")
        }
    }
    public var loadedModels: [String] = []
    public var autoStart = false
    public var maxConcurrentRequests = 4
    
    // MARK: - Private
    
    private var listener: NWListener?
    private let serviceType = "_visualintel._tcp"
    private let port: UInt16 = 8847
    
    // MARK: - Status Icon
    
    public var statusIcon: String {
        switch status {
        case .idle: return "circle"
        case .starting: return "circle.dashed"
        case .listening: return "circle.fill"
        case .processing: return "bolt.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
    
    // MARK: - Lifecycle
    
    public init() {
        // Auto-discover available models
        loadedModels = discoverModels()
        
        // Auto-download highest tier models on first run
        Task { await autoProvisionModels() }
        
        if autoStart {
            startListening()
        }
    }
    
    public func startListening() {
        guard !isListening else { return }
        status = .starting
        
        do {
            // TCP parameters (local network)
            let params = NWParameters.tcp
            // params.includePeerToPeer = true // Not required for plain TCP
            
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            // Advertise via Bonjour with TXT record metadata
            var txtRecord = NWTXTRecord()
            let hw = CapabilityRouter.shared.currentCapability
            txtRecord["chip"] = hw.chipFamily
            txtRecord["tops"] = String(format: "%.1f", hw.neuralEngineTOPS)
            txtRecord["ram"] = "\(hw.physicalMemoryGB)"
            txtRecord["models"] = loadedModels.joined(separator: ",")
            
            print("📡 EdgeDaemon TXT record: chip=\(hw.chipFamily), tops=\(hw.neuralEngineTOPS), ram=\(hw.physicalMemoryGB)GB, models=\(loadedModels.joined(separator: ","))")
            
#if os(macOS)
            let nodeName = Host.current().localizedName ?? "Mac Edge Node"
#else
            let nodeName = ProcessInfo.processInfo.hostName
#endif
            
            listener.service = NWListener.Service(
                name: nodeName,
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
    
    public func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
        status = .idle
        connectedClients.removeAll()
        print("🔴 EdgeDaemon: Stopped")
    }
    
    private var activeConnections: [NWConnection] = []
    
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
        let clientInterface = connection.currentPath?.availableInterfaces.first?.name ?? "unknown interface"
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectedClients.append(clientName)
                    self.activeConnections.append(connection)
                    print("🔗 EdgeDaemon: Client connected: \(clientName) [\(clientInterface)]")
                    // Eagerly pre-load CLaRa 7B into unified memory so Agentic Search is instant
                    Task {
                        try? await CLaRaLatentService.shared.loadModel()
                    }
                case .cancelled, .failed:
                    self.connectedClients.removeAll { $0 == clientName }
                    self.activeConnections.removeAll { $0 === connection }
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
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ EdgeDaemon: Receive error: \(error)")
                connection.cancel()
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            guard let header = content, header.count == 4 else {
                connection.cancel()
                return
            }
            
            let frameLength = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            guard frameLength < 50_000_000 else {
                print("⚠️ EdgeDaemon: Frame length exceeds limit (\(frameLength) bytes)")
                connection.cancel()
                return
            } // 50MB limit
            
            connection.receive(
                minimumIncompleteLength: Int(frameLength),
                maximumLength: Int(frameLength)
            ) { [weak self] body, _, isBodyComplete, bodyError in
                guard let self = self else { return }
                
                if let bodyError = bodyError {
                    print("⚠️ EdgeDaemon: Body receive error: \(bodyError)")
                    connection.cancel()
                    return
                }
                guard let body = body else {
                    connection.cancel()
                    return
                }
                
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
                    
                    connection.send(content: frame, isComplete: false, completion: .contentProcessed { [weak self] sendError in
                        guard let self = self else { return }
                        if let sendError = sendError {
                            print("⚠️ EdgeDaemon: Send error: \(sendError)")
                            connection.cancel()
                            return
                        }
                        
                        Task { @MainActor in
                            self.status = .listening
                        }
                        
                        if isBodyComplete {
                            // Client has explicitly terminated the stream
                            connection.cancel()
                            return
                        }
                        
                        // Successfully responded, queue up next read on this persistent tunnel
                        self.receiveMessages(on: connection)
                    })
                }
            }
        }
    }
    
    // MARK: - Request Processing
    
    nonisolated private func getNodeName() -> String {
#if os(macOS)
        return Host.current().localizedName ?? "Edge Node"
#else
        return ProcessInfo.processInfo.hostName
#endif
    }
    
    nonisolated private func processRequest(_ data: Data) async -> Data {
        let startTime = CFAbsoluteTimeGetCurrent()
        let nodeName = getNodeName()
        
        // Unpack framing: [4-byte target length][target string][payload]
        guard data.count >= 4 else {
            print("❌ EdgeDaemon: Payload too small (\(data.count) bytes)")
            return Data()
        }
        
        let targetLength = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        guard data.count >= 4 + Int(targetLength) else {
            print("❌ EdgeDaemon: Payload malformed. Expected at least \(4 + targetLength) bytes, got \(data.count)")
            return Data()
        }
        
        let targetData = data.dropFirst(4).prefix(Int(targetLength))
        let payload = Data(data.dropFirst(4 + Int(targetLength)))
        
        let method = String(data: targetData, encoding: .utf8) ?? "unknown"
        print("📨 EdgeDaemon: Processing '\(method)' payload (\(payload.count) bytes)")
        
        // Fast-path: capabilities query (no enqueue needed)
        if method == "__capabilities__" {
            let hw = CapabilityRouter.shared.currentCapability
            let caps: [String: Any] = [
                "chip": hw.chipFamily,
                "tops": hw.neuralEngineTOPS,
                "ram": hw.physicalMemoryGB,
                "models": self.discoverModels()
            ]
            let capsData = (try? JSONSerialization.data(withJSONObject: caps)) ?? Data()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ EdgeDaemon: '__capabilities__' responded in \(String(format: "%.0f", elapsed * 1000))ms")
            return capsData
        }
        
        do {
            let resultData = try await EdgeQueueManager.shared.enqueue {
                let dummySystem = VisualIntelligenceActorSystem(transport: NWTransportLayer(localNodeName: "daemon"))
                let encodedResult: Data
                
                if method == "vision" || (method.contains("EdgeInferenceActor") && method.contains("analyzeImage")) {
                    let imageData: Data
                    if method == "vision" { imageData = payload } else {
                        let decoder = try EdgeInvocationDecoder(data: payload)
                        imageData = try decoder.decodeNextArgument()
                    }
                    let actor = EdgeInferenceActor(actorSystem: dummySystem)
                    let visionResult = try await actor.analyzeImage(imageData)
                    encodedResult = try JSONEncoder().encode(visionResult)
                    
                } else if method == "vlm" || (method.contains("EdgeInferenceActor") && method.contains("runVLM")) {
                    let imageData: Data
                    let prompt: String
                    if method == "vlm" {
                        imageData = payload
                        prompt = ""
                    } else {
                        let decoder = try EdgeInvocationDecoder(data: payload)
                        imageData = try decoder.decodeNextArgument()
                        prompt = try decoder.decodeNextArgument()
                    }
                    let actor = EdgeInferenceActor(actorSystem: dummySystem)
                    let vlmResult = try await actor.runVLM(imageData: imageData, prompt: prompt)
                    encodedResult = try JSONEncoder().encode(vlmResult)
                    
                } else if method == "nowcast" || (method.contains("EdgeNowcastingActor") && method.contains("project")) {
                    let commodityID: String
                    let horizonDays: Int
                    if method == "nowcast" {
                        let params = try JSONDecoder().decode(NowcastRequest.self, from: payload)
                        commodityID = params.commodityID
                        horizonDays = params.horizonDays
                    } else {
                        let decoder = try EdgeInvocationDecoder(data: payload)
                        commodityID = try decoder.decodeNextArgument()
                        horizonDays = try decoder.decodeNextArgument()
                    }
                    let actor = EdgeNowcastingActor(actorSystem: dummySystem)
                    let trajectory = try await actor.project(commodityID: commodityID, horizonDays: horizonDays)
                    encodedResult = try JSONEncoder().encode(trajectory)
                    
                } else if method == "gov" || (method.contains("EdgeESGActor") && method.contains("fetchGovernmentData")) {
                    let product: ProductClassification
                    if method == "gov" {
                        product = try JSONDecoder().decode(ProductClassification.self, from: payload)
                    } else {
                        let decoder = try EdgeInvocationDecoder(data: payload)
                        product = try decoder.decodeNextArgument()
                    }
                    let actor = EdgeESGActor(actorSystem: dummySystem)
                    let enrichment = try await actor.fetchGovernmentData(product: product)
                    encodedResult = try JSONEncoder().encode(enrichment)
                    
                } else if method == "commerce" || (method.contains("EdgeCommerceActor") && method.contains("rankPlatforms")) {
                    let product: ProductClassification
                    let policy: EthicalPolicy
                    if method == "commerce" {
                        let params = try JSONDecoder().decode(CommerceRequest.self, from: payload)
                        product = params.product
                        policy = params.policy
                    } else {
                        let decoder = try EdgeInvocationDecoder(data: payload)
                        product = try decoder.decodeNextArgument()
                        policy = try decoder.decodeNextArgument()
                    }
                    let actor = EdgeCommerceActor(actorSystem: dummySystem)
                    let platforms = try await actor.rankPlatforms(product: product, policy: policy)
                    encodedResult = try JSONEncoder().encode(platforms)
                    
                } else if method.contains("EdgeESGActor") && method.contains("fetchCompanyESG") {
                    let decoder = try EdgeInvocationDecoder(data: payload)
                    let brand: String = try decoder.decodeNextArgument()
                    let actor = EdgeESGActor(actorSystem: dummySystem)
                    let profile = try await actor.fetchCompanyESG(brand: brand)
                    encodedResult = try JSONEncoder().encode(profile)
                    
                } else if method.contains("EdgeFinancialActor") && method.contains("projectBudgetImpact") {
                    let decoder = try EdgeInvocationDecoder(data: payload)
                    let price: Decimal = try decoder.decodeNextArgument()
                    let quantity: Int = try decoder.decodeNextArgument()
                    let actor = EdgeFinancialActor(actorSystem: dummySystem)
                    let impact = try await actor.projectBudgetImpact(productPrice: price, quantity: quantity)
                    encodedResult = try JSONEncoder().encode(impact)
                    
                } else if method.contains("EdgeAgenticSearchActor") && method.contains("search") {
                    let decoder = try EdgeInvocationDecoder(data: payload)
                    let query: AgenticSearchQuery = try decoder.decodeNextArgument()
                    let actor = EdgeAgenticSearchActor(actorSystem: dummySystem)
                    let result = try await actor.search(query: query)
                    encodedResult = try JSONEncoder().encode(result)
                    
                } else if method.contains("EdgeAgenticSearchActor") && method.contains("ingest") {
                    let decoder = try EdgeInvocationDecoder(data: payload)
                    let ingestPayload: AgenticSearchIngestPayload = try decoder.decodeNextArgument()
                    let actor = EdgeAgenticSearchActor(actorSystem: dummySystem)
                    let result = try await actor.ingest(payload: ingestPayload)
                    encodedResult = try JSONEncoder().encode(result)
                    
                } else if method.contains("EdgeContextActor") && method.contains("summarizeStructured") {
                    // Must check BEFORE "summarize" since "summarizeStructured" contains "summarize"
                    let decoder = try EdgeInvocationDecoder(data: payload)
                    let text: String = try decoder.decodeNextArgument()
                    var imageData: Data? = nil
                    do {
                        imageData = try decoder.decodeNextArgument() as Data
                    } catch {
                        print("⚠️ EdgeDaemon: Failed to decode imageData for summarizeStructured: \(error)")
                    }
                    print("📦 EdgeDaemon: summarizeStructured text=\(text.count) chars, imageData=\(imageData?.count ?? 0) bytes")
                    let actor = EdgeContextActor(actorSystem: dummySystem)
                    let result = try await actor.summarizeStructured(text: text, imageData: imageData)
                    print("✅ EdgeDaemon: summarizeStructured summary=\(result.summary?.prefix(100) ?? "nil"), tags=\(result.tags.count), statements=\(result.statements.count)")
                    encodedResult = try JSONEncoder().encode(result)
                    
                } else if method.contains("EdgeContextActor") && method.contains("summarize") {
                    let decoder = try EdgeInvocationDecoder(data: payload)
                    let text: String = try decoder.decodeNextArgument()
                    var imageData: Data? = nil
                    do {
                        imageData = try decoder.decodeNextArgument() as Data
                    } catch {
                        print("⚠️ EdgeDaemon: Failed to decode imageData for summarize: \(error)")
                    }
                    print("📦 EdgeDaemon: summarize text=\(text.count) chars, imageData=\(imageData?.count ?? 0) bytes")
                    let actor = EdgeContextActor(actorSystem: dummySystem)
                    let result = try await actor.summarize(text: text, imageData: imageData)
                    print("✅ EdgeDaemon: summarize result=\(result.count) chars")
                    encodedResult = try JSONEncoder().encode(result)
                    
                } else {
                    print("⚠️ EdgeDaemon: Unknown method: \(method)")
                    encodedResult = Data()
                }
                
                return encodedResult
            }
            // The resultData is ALREADY JSONEncoded within each actor invocation block above.
            // We just return it directly so the iOS target can decode(Res.self)
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("✅ EdgeDaemon: Completed '\(method)' in \(String(format: "%.1f", elapsed))ms (Response: \(resultData.count) bytes)")
            
            return resultData
            
        } catch {
            print("❌ EdgeDaemon: Request '\(method)' failed: \(error)")
            // Return empty response on error
            let emptyData = Data()
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("⚠️ EdgeDaemon: Aborted '\(method)' in \(String(format: "%.1f", elapsed))ms")
            
            return emptyData
        }
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
    
    // MARK: - Model Download
    
    nonisolated public func downloadModel(name: String) async {
        let fastVLMTiers = [
            ("mlx-community/FastVLM-0.5B-bf16", "fastvlm-0.5b"),
            // 1.5B maps to 0.5B — Apple released PyTorch checkpoint but no MLX port exists
            ("mlx-community/FastVLM-0.5B-bf16", "fastvlm-1.5b"),
            // 7B removed — llava_qwen2 architecture unsupported by mlx_vlm converter
        ]
        
        guard let match = fastVLMTiers.first(where: { $0.1 == name }) else {
            print("⚠️ EdgeDaemon: Model '\(name)' not found. Available models: fastvlm-0.5b, fastvlm-1.5b")
            return
        }
        
        let repoId = match.0
        let folderName = name.replacingOccurrences(of: "fastvlm-", with: "").uppercased()
        
        print("⏳ Downloading model: \(name) from \(repoId) ...")

        
        do {
            let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!.appendingPathComponent("Models/FastVLM")
            let targetDir = modelsDir.appendingPathComponent(folderName)
            
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            
            let requiredFiles = [
                "config.json",
                "model.safetensors",
                "tokenizer.json",
                "tokenizer_config.json",
                "preprocessor_config.json"
            ]
            
            for file in requiredFiles {
                let urlStr = "https://huggingface.co/\(repoId)/resolve/main/\(file)"
                guard let url = URL(string: urlStr) else { continue }
                
                print("   ... downloading \(file) from \(urlStr)")
        
                
                let (tempURL, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) in
                    let delegate = ConsoleDownloadDelegate(continuation)
                    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                    session.downloadTask(with: url).resume()
                    session.finishTasksAndInvalidate()
                }
                
                print("   ... finished \(file) with HTTP \(response.statusCode)")
        
                defer { try? FileManager.default.removeItem(at: tempURL) }
                
                guard response.statusCode == 200 else {
                    print("⚠️ EdgeDaemon: Failed to download \(file) (HTTP \(response.statusCode))")
                    continue
                }
                
                let dest = targetDir.appendingPathComponent(file)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
            }
            
            print("\n✅ EdgeDaemon: Successfully downloaded \(name) to \(targetDir.path)")
            
            // Re-discover models and update loadedModels array
            let newlyDiscovered = discoverModels()
            await MainActor.run {
                self.loadedModels = newlyDiscovered
            }
            
        } catch {
            print("⚠️ EdgeDaemon: Download failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Download Delegate Helper
    
    private final class ConsoleDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
        private let continuationBox: UnsafeContinuationBox
        nonisolated(unsafe) private var lastPrinted: Int = -1
        private let printLock = NSLock()
        
        init(_ continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) {
            self.continuationBox = UnsafeContinuationBox(continuation)
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 {
                let percent = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
                
                printLock.lock()
                let last = lastPrinted
                if percent % 5 == 0 && percent != last {
                    let writtenMB = Double(totalBytesWritten) / 1_048_576.0
                    let totalMB = Double(totalBytesExpectedToWrite) / 1_048_576.0
                    print(String(format: "⏳ Downloading... %d%% (%.2f MB / %.2f MB)", percent, writtenMB, totalMB))
                    lastPrinted = percent
                }
                printLock.unlock()
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.copyItem(at: location, to: temp)
            if let response = downloadTask.response as? HTTPURLResponse {
                continuationBox.resume(returning: (temp, response))
            } else {
                continuationBox.resume(throwing: URLError(.badServerResponse))
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                continuationBox.resume(throwing: error)
            }
        }
    }
    
    private final class UnsafeContinuationBox: @unchecked Sendable {
        private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
        private let lock = NSLock()
        
        init(_ continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) {
            self.continuation = continuation
        }
        
        func resume(returning value: (URL, HTTPURLResponse)) {
            lock.lock()
            defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }
        
        func resume(throwing error: Error) {
            lock.lock()
            defer { lock.unlock() }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
    
    nonisolated private func discoverModels() -> [String] {
        var models = ["vision-pipeline"]
        
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Models")
        
        guard let dir = modelsDir else { return models }
        
        // Check for each FastVLM tier installed from HF
        let fastVLMTiers = [
            ("0.5B", "fastvlm-0.5b"),
            ("1.5B", "fastvlm-1.5b"),
            // 7B removed — llava_qwen2 architecture unsupported by mlx_vlm converter
        ]
        
        for (folder, modelID) in fastVLMTiers {
            let configPath = dir.appendingPathComponent("FastVLM/\(folder)/config.json").path
            if FileManager.default.fileExists(atPath: configPath) {
                models.append(modelID)
            }
        }
        
        // Check for YOLO CoreML model
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("YOLOv8.mlmodelc").path) {
            models.append("yolov8-coreml")
        }
        
        // Check for SAM 2.1 CoreML model
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("sam2.1-small.mlpackage").path) {
            models.append("sam-2.1")
        }
        
        // Check for CLaRa MLX model
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("CLaRa/model.safetensors.index.json").path) {
            models.append("clara-7b-mlx")
        }
        
        // Check for ML-Sharp python scripts
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("ml-sharp/enhance.py").path) {
            models.append("ml-sharp")
        }
        
        return models
    }
    
    // MARK: - Auto-Provisioning
    
    private func autoProvisionModels() async {
        // Delegate provisioning of SAM 2.1, ML-Sharp, FastVLM, and CLaRa to the centralized Swift orchestrator
        await EdgeModelProvisioner.shared.provisionAll()
        
        // Rediscover models after provisioning is complete
        await MainActor.run {
            self.loadedModels = discoverModels()
        }
    }
    
    // MARK: - Local CLI Chat Interface
    
    /// Starts an interactive terminal chat REPL utilizing the local CLaRa model.
    public func startChatREPL() async {
        print("\n=============================================")
        print("🧠 CLaRa Agentic Search (Data Spaces)        ")
        print("Type your query. Type 'exit' to return to CLI")
        print("=============================================\n")
        
        // CLaRa latent simulation path (until we have real cross-device sync for latents)
        let contextText = "This simulates a semantic context block representing the user's visual memory."
            
        guard CLaRaLatentService.shared.isAvailable else {
            print("⚠️ CLaRa weights not found. Please wait for EdgeModelProvisioner to finish or check your connection.")
            return
        }
        
        // Pre-warm the unified memory cache
        try? await CLaRaLatentService.shared.loadModel()
        
        while true {
            print("\nclara> ", terminator: "")
    
            
            guard let input = readLine() else { break }
            let queryText = input.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if queryText.lowercased() == "exit" || queryText.lowercased() == "quit" {
                print("Exiting chat. Returning to EdgeDaemon CLI.\n")
                break
            }
            
            guard !queryText.isEmpty else { continue }
            print("⏳ Thinking...")
            
            do {
                if let answer = try await CLaRaLatentService.shared.query(documentText: contextText, question: queryText) {
                    print("\n🤖 CLaRa:")
                    print(answer)
                } else {
                    print("\n⚠️ Failed to generate CLaRa output.")
                }
            } catch {
                print("\n⚠️ Failed to run CLaRa: \(error)")
            }
        }
    }
}
