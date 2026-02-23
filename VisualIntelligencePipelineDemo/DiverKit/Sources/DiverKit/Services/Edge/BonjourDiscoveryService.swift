//
//  BonjourDiscoveryService.swift
//  DiverKit
//
//  Discovers edge nodes on the local network using NWBrowser (Bonjour).
//  Conforms to EdgeNodeDiscovering protocol.
//
//  Service type: _visualintel._tcp
//  TXT records carry device metadata (chipFamily, neuralEngineTOPS, models).
//

import Foundation
import Network
import DiverShared

/// Discovers M-series Mac and iPad edge nodes on the local network via Bonjour.
/// Conforms to EdgeNodeDiscovering protocol.
public actor BonjourDiscoveryService: EdgeNodeDiscovering {
    
    // MARK: - Constants
    
    nonisolated public static let serviceType = "_visualintel._tcp"
    
    // MARK: - State
    
    private var browser: NWBrowser?
    private var discoveredNodes: [EdgeNodeInfo] = []
    private var isScanning = false
    private var reconnectTask: Task<Void, Never>?
    private let reconnectInterval: Duration = .seconds(10)
    
    // MARK: - EdgeNodeDiscovering
    
    public var availableNodes: [EdgeNodeInfo] {
        discoveredNodes
    }
    
    public var connectedNode: EdgeNodeInfo? {
        currentConnection
    }
    
    public var currentConnection: EdgeNodeInfo? {
        didSet {
            // Only fire callback when connecting to a NEW device (not just updating capabilities)
            if let node = currentConnection,
               node.deviceName != oldValue?.deviceName {
                onNodeConnected?(node.deviceName)
            }
        }
    }
    
    private var onNodeConnected: (@Sendable (String) -> Void)?
    
    public var isEdgeNodeConnected: Bool {
        currentConnection != nil
    }
    
    // MARK: - Lifecycle
    
    public init() {}
    
    public func setOnNodeConnected(_ handler: (@Sendable (String) -> Void)?) {
        self.onNodeConnected = handler
    }
    
    public func startDiscovery() {
        guard !isScanning else { return }
        isScanning = true
        
        let params = NWParameters()
        params.includePeerToPeer = true
        
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: params
        )
        
        browser.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleBrowserState(state)
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { [weak self] in
                await self?.handleResultsChanged(results: results, changes: changes, retryCount: 0)
            }
        }
        
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
        
        print("🔍 BonjourDiscovery: Started scanning for edge nodes (\(Self.serviceType))")
    }
    
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isScanning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        print("🔍 BonjourDiscovery: Stopped scanning")
    }
    
    public func connect(to node: EdgeNodeInfo) async throws {
        guard discoveredNodes.contains(node) else {
            throw BonjourError.nodeNotFound(node.deviceName)
        }
        currentConnection = node
        print("🔗 BonjourDiscovery: Connected to \(node.deviceName) (\(node.chipFamily))")
    }
    
    public func disconnect() {
        if let node = currentConnection {
            print("🔗 BonjourDiscovery: Disconnected from \(node.deviceName)")
        }
        currentConnection = nil
    }
    
    /// Update a discovered node's capabilities from a TCP `__capabilities__` RPC response.
    /// Called after establishing TCP connection, since NWBrowser TXT metadata is unreliable.
    public func updateNodeFromCapabilities(_ data: Data, nodeName: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("⚠️ BonjourDiscovery: Failed to parse capabilities JSON from \(nodeName)")
            return
        }
        
        let chip = json["chip"] as? String ?? "Unknown"
        let tops = (json["tops"] as? NSNumber)?.floatValue ?? 0
        let ram = (json["ram"] as? NSNumber)?.uint64Value ?? 0
        let models = json["models"] as? [String] ?? []
        
        let updatedNode = EdgeNodeInfo(
            deviceName: nodeName,
            chipFamily: chip,
            neuralEngineTOPS: tops,
            physicalMemoryGB: ram,
            availableModels: models,
            isAvailable: true
        )
        
        // Replace the node in discoveredNodes
        if let idx = discoveredNodes.firstIndex(where: { $0.deviceName == nodeName }) {
            discoveredNodes[idx] = updatedNode
        }
        
        // Update currentConnection if it matches
        if currentConnection?.deviceName == nodeName {
            currentConnection = updatedNode
        }
        
        print("✅ BonjourDiscovery: Updated \(nodeName) via TCP — chip=\(chip), tops=\(tops), ram=\(ram)GB, models=\(models)")
    }
    
    /// Explicitly mark a node as unavailable when a TCP connection fails (e.g. stale mDNS cache).
    public func markNodeUnavailable(nodeName: String) {
        if let idx = discoveredNodes.firstIndex(where: { $0.deviceName == nodeName }) {
            var node = discoveredNodes[idx]
            node.isAvailable = false
            discoveredNodes[idx] = node
        }
        
        if currentConnection?.deviceName == nodeName {
            print("⚠️ BonjourDiscovery: Marked current connection \(nodeName) as unavailable due to timeout.")
            currentConnection = nil
            scheduleReconnect(reason: "connection failed")
        } else {
            print("⚠️ BonjourDiscovery: Marked \(nodeName) as unavailable.")
        }
    }
    
    // MARK: - Browser Handlers
    
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("🔍 BonjourDiscovery: Browser ready")
        case .failed(let error):
            print("⚠️ BonjourDiscovery: Browser failed: \(error)")
            isScanning = false
            // Auto-restart discovery after failure (WiFi reconnect, etc.)
            scheduleReconnect(reason: "browser failure")
        case .cancelled:
            isScanning = false
        default:
            break
        }
    }
    
    private func handleResultsChanged(
        results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>,
        retryCount: Int
    ) {
        // Local device names to ignore
#if os(macOS)
        let localName = Host.current().localizedName ?? "Mac Edge Node"
#else
        let localName = ProcessInfo.processInfo.hostName
#endif

        var hasNilMetadata = false
        
        discoveredNodes = results.compactMap { result -> EdgeNodeInfo? in
            // Extract service name from endpoint
            let name: String
            switch result.endpoint {
            case .service(let svcName, _, _, _):
                name = svcName
            default:
                return nil
            }
            
            // Ignore ourselves
            if name == localName {
                return nil
            }
            
            // Parse TXT record metadata
            let metadata = parseTXTRecord(from: result.metadata)
            
            if metadata.isEmpty {
                hasNilMetadata = true
            }
            
            let nodeInfo = EdgeNodeInfo(
                deviceName: name,
                chipFamily: metadata["chip"] ?? "Unknown",
                neuralEngineTOPS: Float(metadata["tops"] ?? "0") ?? 0,
                physicalMemoryGB: UInt64(metadata["ram"] ?? "0") ?? 0,
                availableModels: metadata["models"]?.components(separatedBy: ",") ?? [],
                isAvailable: true
            )
            print("🔍 BonjourDiscovery: Parsed TXT for \(name) — chip=\(nodeInfo.chipFamily), tops=\(nodeInfo.neuralEngineTOPS), ram=\(nodeInfo.physicalMemoryGB)GB, models=\(nodeInfo.availableModels)")
            return nodeInfo
        }
        
        let sortedNodes = discoveredNodes.sorted {
            // Primary: highest TOPS. Secondary: highest RAM (breaks ties when TXT not yet resolved = 0 TOPS).
            if $0.neuralEngineTOPS != $1.neuralEngineTOPS {
                return $0.neuralEngineTOPS > $1.neuralEngineTOPS
            }
            return $0.physicalMemoryGB > $1.physicalMemoryGB
        }
        if let bestNode = sortedNodes.first {
            if currentConnection?.deviceName != bestNode.deviceName {
                currentConnection = bestNode
                print("🔗 BonjourDiscovery: Auto-connected to best node = \(bestNode.deviceName) (\(bestNode.neuralEngineTOPS) TOPS, \(bestNode.physicalMemoryGB)GB RAM)")
                // `currentConnection` property observer `didSet` automatically triggers `onNodeConnected?(bestNode.deviceName)`.
                // A duplicate explicit call here was removed to prevent multi-connections.
            }
        } else {
            if currentConnection != nil {
                print("⚠️ BonjourDiscovery: Lost connection to \(currentConnection!.deviceName)")
            }
            currentConnection = nil
            // Node disappeared — start polling for reconnection
            scheduleReconnect(reason: "node lost")
        }
        
        print("🔍 BonjourDiscovery: \(discoveredNodes.count) node(s) found")
        
        // TXT records resolve asynchronously over mDNS. If any node had nil metadata,
        // do one delayed retry using the browser's LIVE results (not cached snapshots).
        if hasNilMetadata && retryCount == 0 {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                guard let liveBrowser = await self.browser else { return }
                let liveResults = liveBrowser.browseResults
                print("🔄 BonjourDiscovery: One-time TXT retry with \(liveResults.count) live result(s)...")
                await self.handleResultsChanged(results: liveResults, changes: [], retryCount: 1)
            }
        }
    }
    
    // MARK: - Reconnection Polling
    
    /// Schedules periodic reconnection attempts when an edge node is lost.
    /// Cancels automatically when a node reconnects or discovery is stopped.
    private func scheduleReconnect(reason: String) {
        // Don't stack multiple reconnect timers
        guard reconnectTask == nil else { return }
        
        print("🔄 BonjourDiscovery: Scheduling reconnect polling (\(reason))...")
        
        reconnectTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { break }
                
                // If we've reconnected, stop polling
                if await self.currentConnection != nil {
                    print("✅ BonjourDiscovery: Reconnected — stopping poll")
                    break
                }
                
                print("🔄 BonjourDiscovery: Reconnect attempt #\(attempt)...")
                
                // Restart the browser to scan fresh
                await self.restartBrowser()
            }
            await self?.clearReconnectTask()
        }
    }
    
    /// Clears the reconnect task reference (actor-isolated).
    private func clearReconnectTask() {
        reconnectTask = nil
    }
    
    /// Restarts the NWBrowser for a fresh scan.
    private func restartBrowser() {
        browser?.cancel()
        browser = nil
        isScanning = false
        startDiscovery()
    }
    
    /// Parse Bonjour TXT record entries.
    private func parseTXTRecord(from metadata: NWBrowser.Result.Metadata?) -> [String: String] {
        guard let metadata = metadata,
              case .bonjour(let txtRecord) = metadata else {
            print("⚠️ BonjourDiscovery: No TXT metadata — metadata is nil or not bonjour")
            return [:]
        }
        
        var dict: [String: String] = [:]
        
        // Debug: dump TXT record description and all known keys
        print("🔍 BonjourDiscovery: TXT record = \(String(describing: txtRecord))")
        
        // Try standard NWTXTRecord subscript access
        for key in ["chip", "tops", "ram", "models"] {
            if let value = txtRecord[key] {
                dict[key] = value
                print("🔍 BonjourDiscovery: TXT[\(key)] = \(value)")
            } else {
                print("⚠️ BonjourDiscovery: TXT[\(key)] = nil")
            }
        }
        
        return dict
    }
}

// MARK: - Errors

public enum BonjourError: Error, LocalizedError {
    case nodeNotFound(String)
    case connectionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .nodeNotFound(let name): return "Edge node '\(name)' not found on network"
        case .connectionFailed(let name): return "Failed to connect to '\(name)'"
        }
    }
}
