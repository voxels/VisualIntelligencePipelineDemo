//
//  MockEdgeNodeService.swift
//  DiverKit
//
//  Mock implementation of EdgeNodeDiscovering for isolated unit testing.
//

import Foundation
import DiverShared
@testable import DiverKit

public final class MockEdgeNodeService: EdgeNodeDiscovering, @unchecked Sendable {
    
    public var availableNodes: [EdgeNodeInfo] = []
    public var connectedNode: EdgeNodeInfo? = nil
    
    public var isEdgeNodeConnected: Bool {
        return connectedNode != nil
    }
    
    private var onNodeConnectedHandler: (@Sendable (String) -> Void)?
    
    public init() {}
    
    public func setOnNodeConnected(_ handler: (@Sendable (String) -> Void)?) async {
        self.onNodeConnectedHandler = handler
    }
    
    public func startDiscovery() async {
        // Mock start scanning
    }
    
    public func stopDiscovery() async {
        // Mock stop scanning
    }
    
    public func connect(to node: EdgeNodeInfo) async throws {
        self.connectedNode = node
        onNodeConnectedHandler?(node.deviceName)
    }
    
    public func disconnect() async {
        self.connectedNode = nil
    }
    
    // Test Helpers
    public func simulateNodeDiscovery(node: EdgeNodeInfo) {
        availableNodes.append(node)
    }
}
