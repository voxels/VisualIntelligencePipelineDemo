//
//  VisualIntelligenceActorSystem.swift
//  DiverKit
//
//  Custom DistributedActorSystem for the Visual Intelligence edge computing network.
//  Handles serialization, transport, and actor lifecycle for distributed actors
//  communicating between iOS clients and M-series Mac/iPad edge nodes.
//
//  Uses Network framework (NWConnection) for TLS 1.3 encrypted transport
//  over the local network, discovered via Bonjour.
//

import Foundation
import Distributed
import DiverShared

// MARK: - Actor System

/// Custom DistributedActorSystem for local network ML offloading.
/// Manages actor identity, serialization, and remote method invocation.
public final class VisualIntelligenceActorSystem: DistributedActorSystem, Sendable {
    public typealias ActorID = EdgeActorID
    public typealias InvocationEncoder = EdgeInvocationEncoder
    public typealias InvocationDecoder = EdgeInvocationDecoder
    public typealias SerializationRequirement = Codable
    public typealias ResultHandler = EdgeResultHandler
    
    private let transport: EdgeTransportProtocol
    private let lock = NSLock()
    nonisolated(unsafe) private var localActors: [ActorID: any DistributedActor] = [:]
    
    public init(transport: EdgeTransportProtocol) {
        self.transport = transport
    }
    
    // MARK: - DistributedActorSystem Requirements
    
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
    where Act: DistributedActor, Act.ID == ActorID {
        lock.lock()
        defer { lock.unlock() }
        return localActors[id] as? Act
    }
    
    public func assignID<Act>(_ actorType: Act.Type) -> ActorID
    where Act: DistributedActor, Act.ID == ActorID {
        EdgeActorID(id: UUID().uuidString, nodeName: transport.localNodeName)
    }
    
    public func actorReady<Act>(_ actor: Act)
    where Act: DistributedActor, Act.ID == ActorID {
        lock.lock()
        defer { lock.unlock() }
        localActors[actor.id] = actor
    }
    
    public func resignID(_ id: ActorID) {
        lock.lock()
        defer { lock.unlock() }
        localActors.removeValue(forKey: id)
    }
    
    public func makeInvocationEncoder() -> InvocationEncoder {
        EdgeInvocationEncoder()
    }
    
    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error,
          Res: Codable {
        let payload = try invocation.encode()
        let response = try await transport.send(
            to: actor.id,
            target: target.identifier,
            payload: payload
        )
        
        // Handle primitive raw strings gracefully
        if Res.self == String.self {
            if let str = String(data: response, encoding: .utf8) {
                // If it was double-quoted by JSONEncoder on the edge, strip it
                let cleanStr = str.hasPrefix("\"") && str.hasSuffix("\"") ? String(str.dropFirst().dropLast()) : str
                if let res = cleanStr as? Res {
                    return res
                } else {
                    throw EdgeTransportError.typeMismatch(expected: "String")
                }
            }
        }
        
        // Handle bare Data returns
        if Res.self == Data.self {
            if let res = response as? Res {
                return res
            } else {
                throw EdgeTransportError.typeMismatch(expected: "Data")
            }
        }
        
        do {
            return try JSONDecoder().decode(Res.self, from: response)
        } catch {
            let preview = String(data: response.prefix(200), encoding: .utf8) ?? "<non-utf8, \(response.count) bytes>"
            print("⚠️ [ActorSystem] Failed to decode \(Res.self) from edge response (\(response.count) bytes). Preview: \(preview)")
            throw error
        }
    }
    
    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error {
        let payload = try invocation.encode()
        _ = try await transport.send(
            to: actor.id,
            target: target.identifier,
            payload: payload
        )
    }
}

// MARK: - Actor Identity

/// Unique identity for a distributed actor on the edge network.
public struct EdgeActorID: Codable, Hashable, Sendable {
    public let id: String
    public let nodeName: String  // Which device hosts this actor
    
    public init(id: String, nodeName: String) {
        self.id = id
        self.nodeName = nodeName
    }
}

// MARK: - Invocation Encoding

/// Encodes distributed actor method invocations for transport.
public struct EdgeInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable
    
    private var arguments: [Data] = []
    private var genericSubstitutions: [Any.Type] = []
    
    public init() {}
    
    public mutating func recordArgument<Value: Codable>(
        _ argument: RemoteCallArgument<Value>
    ) throws {
        let data = try JSONEncoder().encode(argument.value)
        arguments.append(data)
    }
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        genericSubstitutions.append(type)
    }
    
    public mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {
        // Return type recorded for invocation metadata
        // In our simple framing, we rely on the target ID string instead.
    }
    
    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {
        // Error type recorded for invocation metadata
    }
    
    public mutating func doneRecording() throws {
        // Finalize encoding
    }
    
    /// Encode all arguments into a single transportable payload.
    func encode() throws -> Data {
        try JSONEncoder().encode(arguments)
    }
}

// MARK: - Invocation Decoding

/// Decodes distributed actor method invocations from transport.
public class EdgeInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable
    
    private var arguments: [Data]
    private var index: Int = 0
    
    public init(data: Data) throws {
        self.arguments = try JSONDecoder().decode([Data].self, from: data)
    }
    
    public func decodeNextArgument<Argument: Codable>() throws -> Argument {
        guard index < arguments.count else {
            throw EdgeTransportError.argumentDecodingFailed
        }
        let data = arguments[index]
        index += 1
        return try JSONDecoder().decode(Argument.self, from: data)
    }
    
    public func decodeGenericSubstitutions() throws -> [Any.Type] {
        []  // We do not rely on generic substitutions encoded to transport
    }
    
    public func decodeReturnType() throws -> Any.Type? {
        nil // Return type inferred natively from call site
    }
    
    public func decodeErrorType() throws -> Any.Type? {
        nil // Error type natively inferred
    }
}

// MARK: - Result Handler

/// Handles results from distributed calls.
public struct EdgeResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable
    
    public let completion: @Sendable (Data) -> Void
    
    public func onReturn<Success: Codable>(value: Success) async throws {
        let data = try JSONEncoder().encode(value)
        completion(data)
    }
    
    public func onReturnVoid() async throws {
        completion(Data())
    }
    
    public func onThrow<Err: Error>(error: Err) async throws {
        // Error handling — could encode error for transport
        throw error
    }
}

// MARK: - Transport Protocol

/// Protocol for the network transport layer.
public protocol EdgeTransportProtocol: Sendable {
    var localNodeName: String { get }
    
    func connect(to nodeName: String) async throws
    func send(to actorID: EdgeActorID, target: String, payload: Data) async throws -> Data
}

// MARK: - Transport Errors

public enum EdgeTransportError: Error, LocalizedError {
    case connectionFailed
    case timeout
    case actorNotFound(EdgeActorID)
    case argumentDecodingFailed
    case responseTooLarge
    case typeMismatch(expected: String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Edge node connection failed"
        case .timeout: return "Edge node request timed out"
        case .actorNotFound(let id): return "Actor '\(id.id)' not found on node '\(id.nodeName)'"
        case .argumentDecodingFailed: return "Failed to decode remote call arguments"
        case .responseTooLarge: return "Response exceeds size limit"
        case .typeMismatch(let expected): return "Failed to cast actor response to expected type: \(expected)"
        }
    }
}
