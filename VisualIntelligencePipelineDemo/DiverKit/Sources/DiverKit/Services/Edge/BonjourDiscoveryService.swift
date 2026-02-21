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
    
    // MARK: - EdgeNodeDiscovering
    
    public var availableNodes: [EdgeNodeInfo] {
        discoveredNodes
    }
    
    public var connectedNode: EdgeNodeInfo? {
        currentConnection
    }
    
    public var currentConnection: EdgeNodeInfo? {
        didSet {
            if let node = currentConnection {
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
                await self?.handleResultsChanged(results: results, changes: changes)
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
    
    // MARK: - Browser Handlers
    
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("🔍 BonjourDiscovery: Browser ready")
        case .failed(let error):
            print("⚠️ BonjourDiscovery: Browser failed: \(error)")
            isScanning = false
        case .cancelled:
            isScanning = false
        default:
            break
        }
    }
    
    private func handleResultsChanged(
        results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>
    ) {
        // Local device names to ignore
#if os(macOS)
        let localName = Host.current().localizedName ?? "Mac Edge Node"
#else
        let localName = ProcessInfo.processInfo.hostName
#endif

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
            
            return EdgeNodeInfo(
                deviceName: name,
                chipFamily: metadata["chip"] ?? "Unknown",
                neuralEngineTOPS: Float(metadata["tops"] ?? "0") ?? 0,
                physicalMemoryGB: UInt64(metadata["ram"] ?? "0") ?? 0,
                availableModels: metadata["models"]?.components(separatedBy: ",") ?? [],
                isAvailable: true
            )
        }
        
        let sortedNodes = discoveredNodes.sorted { $0.neuralEngineTOPS > $1.neuralEngineTOPS }
        if let bestNode = sortedNodes.first {
            if currentConnection?.deviceName != bestNode.deviceName {
                currentConnection = bestNode
                print("🔗 BonjourDiscovery: Auto-connected to highest TOPS node = \(bestNode.deviceName) (\(bestNode.neuralEngineTOPS) TOPS)")
                // `currentConnection` property observer `didSet` automatically triggers `onNodeConnected?(bestNode.deviceName)`.
                // A duplicate explicit call here was removed to prevent multi-connections.
            }
        } else {
            currentConnection = nil
        }
        
        print("🔍 BonjourDiscovery: \(discoveredNodes.count) node(s) found")
    }
    
    /// Parse Bonjour TXT record entries.
    private func parseTXTRecord(from metadata: NWBrowser.Result.Metadata?) -> [String: String] {
        guard let metadata = metadata,
              case .bonjour(let txtRecord) = metadata else { return [:] }
        
        var dict: [String: String] = [:]
        
        // NWTXTRecord supports dictionary-style access
        for key in ["chip", "tops", "ram", "models"] {
            if let value = txtRecord[key] {
                dict[key] = value
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
