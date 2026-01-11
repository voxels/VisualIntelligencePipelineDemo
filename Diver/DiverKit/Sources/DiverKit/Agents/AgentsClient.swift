import Foundation

public final class AgentsClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// Register a new agent or update existing agent registration.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func registerAgent(request: Requests.AgentRegister, requestOptions: RequestOptions? = nil) async throws -> AgentRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/agents/register",
            body: request,
            requestOptions: requestOptions,
            responseType: AgentRead.self
        )
    }

    /// List all registered agents.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func listAgents(requestOptions: RequestOptions? = nil) async throws -> [AgentRead] {
        return try await httpClient.performRequest(
            method: .get,
            path: "/agents",
            requestOptions: requestOptions,
            responseType: [AgentRead].self
        )
    }

    /// Get specific agent details.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getAgent(agentId: String, requestOptions: RequestOptions? = nil) async throws -> AgentRead {
        return try await httpClient.performRequest(
            method: .get,
            path: "/agents/\(agentId)",
            requestOptions: requestOptions,
            responseType: AgentRead.self
        )
    }

    /// Deregister an agent.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func deregisterAgent(agentId: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .delete,
            path: "/agents/\(agentId)",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}