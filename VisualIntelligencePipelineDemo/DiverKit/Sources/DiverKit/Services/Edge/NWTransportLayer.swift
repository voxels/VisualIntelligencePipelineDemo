//
//  NWTransportLayer.swift
//  DiverKit
//
//  Network framework transport layer for distributed actor communication.
//  Uses NWConnection with length-prefixed framing over TCP.
//
//  Protocol: Custom framing over TCP with length-prefixed messages.
//  Discovery: Connects to endpoints discovered via BonjourDiscoveryService.
//
//  IMPORTANT: Requests are serialized per connection to prevent frame
//  interleaving. NWConnection is NOT safe for concurrent send/receive
//  pairs — a second caller's receive would read the first caller's
//  response body bytes as a length header, causing responseTooLarge.
//
//  Self-healing: When any framing error occurs (responseTooLarge,
//  connectionFailed, decode mismatch), the connection is invalidated
//  and the next request creates a fresh one.
//

import Foundation
import Network
import os

/// Serializes send/receive pairs on a single NWConnection.
/// Without this, concurrent callers would interleave frames and corrupt the length-prefixed protocol.
private actor ConnectionSerializer {
    private let connection: NWConnection
    /// Callback to invalidate this connection in the parent transport's stores.
    private let onFramingError: @Sendable (String) -> Void
    
    init(connection: NWConnection, onFramingError: @escaping @Sendable (String) -> Void) {
        self.connection = connection
        self.onFramingError = onFramingError
    }
    
    /// Send a request frame and receive the response, atomically.
    /// Only one caller can be in-flight per connection at a time (actor serialization).
    func sendAndReceive(frame: Data) async throws -> Data {
        // 1. Send the request frame
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, isComplete: false, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        // 2. Receive the response (length-prefixed)
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                // Read 4-byte length header
                connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, _, error in
                    if let error = error {
                        self?.onFramingError("receive header error: \(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let header = content, header.count == 4 else {
                        self?.onFramingError("incomplete header (\(content?.count ?? 0) bytes)")
                        continuation.resume(throwing: EdgeTransportError.connectionFailed)
                        return
                    }
                    
                    let responseLength = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    
                    // Handle 0-length response (daemon error/empty response)
                    guard responseLength > 0 else {
                        print("⚠️ [NWTransport] Empty response from daemon (0 bytes)")
                        continuation.resume(returning: Data())
                        return
                    }
                    
                    guard responseLength < 50_000_000 else { // 50MB limit
                        let hexBytes = header.map { String(format: "%02X", $0) }.joined(separator: " ")
                        let asChars = String(data: header, encoding: .utf8) ?? "<non-utf8>"
                        print("⚠️ [NWTransport] responseTooLarge: header=[\(hexBytes)] (chars='\(asChars)'), decoded length=\(responseLength)")
                        self?.onFramingError("responseTooLarge: decoded \(responseLength) bytes")
                        continuation.resume(throwing: EdgeTransportError.responseTooLarge)
                        return
                    }
                    
                    // Read the response body
                    self?.connection.receive(
                        minimumIncompleteLength: Int(responseLength),
                        maximumLength: Int(responseLength)
                    ) { [weak self] body, _, _, error in
                        if let error = error {
                            self?.onFramingError("receive body error: \(error)")
                            continuation.resume(throwing: error)
                        } else if let body = body {
                            continuation.resume(returning: body)
                        } else {
                            self?.onFramingError("nil body after reading \(responseLength) bytes")
                            continuation.resume(throwing: EdgeTransportError.connectionFailed)
                        }
                    }
                }
            }
        } catch {
            // Connection is likely corrupted — cancel it so we get a fresh one next time
            connection.cancel()
            throw error
        }
    }
}

/// Network framework transport for distributed actor calls.
/// Length-prefixed framing over TCP with per-connection request serialization.
///
/// Self-healing: any framing error invalidates the connection, and the next
/// request automatically creates a fresh TCP connection to the same node.
public final class NWTransportLayer: EdgeTransportProtocol, Sendable {
    
    public let localNodeName: String
    private let connectionStore = OSAllocatedUnfairLock(initialState: [String: NWConnection]())
    private let serializerStore = OSAllocatedUnfairLock(initialState: [String: ConnectionSerializer]())
    
    /// Timeout for individual RPC requests.
    private let requestTimeout: TimeInterval = 30.0
    
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
        let (_, serializer) = try await getOrCreateConnection(to: actorID.nodeName)
        
        // Build the request frame: [4-byte total length][4-byte target length][target][payload]
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
        
        // Serialize send+receive through the actor to prevent frame interleaving
        do {
            return try await serializer.sendAndReceive(frame: frame)
        } catch {
            // If it's a framing error, invalidate so next call reconnects
            invalidateConnection(to: actorID.nodeName)
            throw error
        }
    }
    
    // MARK: - Connection Management
    
    /// Invalidate a connection and remove from stores.
    /// The next call to getOrCreateConnection will establish a fresh TCP connection.
    private func invalidateConnection(to nodeName: String) {
        let conn: NWConnection? = connectionStore.withLock { connections in
            let c = connections.removeValue(forKey: nodeName)
            return c
        }
        serializerStore.withLock { serializers in
            serializers.removeValue(forKey: nodeName)
        }
        conn?.cancel()
        print("🔄 [NWTransport] Invalidated connection to \(nodeName) — next request will reconnect")
    }
    
    /// Get or create a TCP connection and its serializer.
    private func getOrCreateConnection(to nodeName: String) async throws -> (NWConnection, ConnectionSerializer) {
        // Check for existing ready connection (sync access via OSAllocatedUnfairLock)
        let existingConn: NWConnection? = connectionStore.withLock { connections in
            if let conn = connections[nodeName], conn.state == .ready {
                return conn
            }
            return nil
        }
        let existingSerializer: ConnectionSerializer? = serializerStore.withLock { serializers in
            return serializers[nodeName]
        }
        if let conn = existingConn, let ser = existingSerializer {
            return (conn, ser)
        }
        
        // Clean up any stale connection before creating a new one
        connectionStore.withLock { connections in
            if let old = connections.removeValue(forKey: nodeName) {
                old.cancel()
            }
        }
        serializerStore.withLock { serializers in
            serializers.removeValue(forKey: nodeName)
        }
        
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
        let serializer = ConnectionSerializer(connection: connection) { [weak self] reason in
            print("⚠️ [NWTransport] Framing error on \(nodeName): \(reason)")
            self?.invalidateConnection(to: nodeName)
        }
        
        // Store immediately so ARC doesn't deallocate before setup completes
        connectionStore.withLock { connections in
            connections[nodeName] = connection
        }
        serializerStore.withLock { serializers in
            serializers[nodeName] = serializer
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
            // Setup failed, remove from stores
            connectionStore.withLock { connections in
                connections[nodeName] = nil
            }
            serializerStore.withLock { serializers in
                serializers[nodeName] = nil
            }
            throw error
        }
        
        print("🔗 NWTransport: Connected to \(nodeName) (TCP, serialized)")
        return (connection, serializer)
    }
}
