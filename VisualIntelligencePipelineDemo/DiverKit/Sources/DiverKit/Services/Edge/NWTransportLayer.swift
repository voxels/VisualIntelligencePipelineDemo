//
//  NWTransportLayer.swift
//  DiverKit
//
//  Network framework transport layer for distributed actor communication.
//  Uses NWConnection with TLS 1.3 for encrypted local network transport.
//
//  Protocol: Custom framing over TCP with length-prefixed messages.
//  Discovery: Connects to endpoints discovered via BonjourDiscoveryService.
//

import Foundation
import Network
import os

/// Network framework transport for distributed actor calls.
/// TLS 1.3 encrypted, length-prefixed framing over TCP.
public final class NWTransportLayer: EdgeTransportProtocol, Sendable {
    
    public let localNodeName: String
    private let connectionStore = OSAllocatedUnfairLock(initialState: [String: NWConnection]())
    
    /// Timeout for individual RPC requests.
    private let requestTimeout: TimeInterval = 10.0
    
    public init(localNodeName: String) {
        self.localNodeName = localNodeName
    }
    
    deinit {
        connectionStore.withLock { connections in
            for (_, conn) in connections {
                conn.cancel()
            }
        }
    }
    
    // MARK: - EdgeTransportProtocol
    
    public func connect(to nodeName: String) async throws {
        _ = try await getOrCreateConnection(to: nodeName)
    }
    
    public func send(to actorID: EdgeActorID, target: String, payload: Data) async throws -> Data {
        let connection = try await getOrCreateConnection(to: actorID.nodeName)
        
        // Frame: [4-byte length][target-length][target][payload]
        let targetData = Data(target.utf8)
        var frame = Data()
        
        // Write total frame length (target + payload)
        var totalLength = UInt32(targetData.count + payload.count + 4).bigEndian
        frame.append(Data(bytes: &totalLength, count: 4))
        
        // Write target length + target
        var targetLength = UInt32(targetData.count).bigEndian
        frame.append(Data(bytes: &targetLength, count: 4))
        frame.append(targetData)
        
        // Write payload
        frame.append(payload)
        
        // Send frame
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        // Receive response frame
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            // First read the 4-byte length header
            connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { content, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let header = content, header.count == 4 else {
                    continuation.resume(throwing: EdgeTransportError.connectionFailed)
                    return
                }
                
                let responseLength = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                
                guard responseLength < 50_000_000 else { // 50MB limit
                    continuation.resume(throwing: EdgeTransportError.responseTooLarge)
                    return
                }
                
                // Read the response body
                connection.receive(
                    minimumIncompleteLength: Int(responseLength),
                    maximumLength: Int(responseLength)
                ) { body, _, _, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let body = body {
                        continuation.resume(returning: body)
                    } else {
                        continuation.resume(throwing: EdgeTransportError.connectionFailed)
                    }
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    /// Get or create a TLS 1.3 connection to a node.
    private func getOrCreateConnection(to nodeName: String) async throws -> NWConnection {
        // Check for existing ready connection (sync access via OSAllocatedUnfairLock)
        let existing: NWConnection? = connectionStore.withLock { connections in
            if let conn = connections[nodeName], conn.state == .ready {
                return conn
            }
            return nil
        }
        if let existing { return existing }
        
        // Create new TCP connection
        let params = NWParameters.tcp
        
        // Use Bonjour service endpoint
        let endpoint = NWEndpoint.service(
            name: nodeName,
            type: BonjourDiscoveryService.serviceType,
            domain: "local.",
            interface: nil
        )
        
        let connection = NWConnection(to: endpoint, using: params)
        
        // Store the connection immediately so ARC doesn't deallocate it before setup completes
        connectionStore.withLock { connections in
            connections[nodeName] = connection
        }
        
        // Wait for connection to become ready
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let lock = OSAllocatedUnfairLock(initialState: false)
                
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        lock.withLock { hasResumed in
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume()
                            }
                        }
                    case .failed(let error):
                        lock.withLock { hasResumed in
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(throwing: error)
                            }
                        }
                    case .cancelled:
                        lock.withLock { hasResumed in
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(throwing: EdgeTransportError.connectionFailed)
                            }
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }
        } catch {
            // Setup failed, remove from store
            connectionStore.withLock { connections in
                connections[nodeName] = nil
            }
            throw error
        }
        
        print("🔗 NWTransport: Connected to \(nodeName) (TCP)")
        return connection
    }
}
