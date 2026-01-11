import Foundation

public final class ReferencesClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    public func listReferences(limit: Int? = nil, offset: Int? = nil, status: String? = nil, entityType: String? = nil, requestOptions: RequestOptions? = nil) async throws -> [ReferenceRead] {
        return try await httpClient.performRequest(
            method: .get,
            path: "/references",
            queryParams: [
                "limit": limit.map { .int($0) }, 
                "offset": offset.map { .int($0) }, 
                "status": status.map { .string($0) }, 
                "entity_type": entityType.map { .string($0) }
            ],
            requestOptions: requestOptions,
            responseType: [ReferenceRead].self
        )
    }

    public func createReference(request: Requests.ReferenceCreate, requestOptions: RequestOptions? = nil) async throws -> ReferenceRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/references",
            body: request,
            requestOptions: requestOptions,
            responseType: ReferenceRead.self
        )
    }

    /// Fetch a single reference by ID, including reference_metadata and optionally creators.
    ///
    /// - Parameter includeCreators: Include creators linked to this reference
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getReference(referenceId: String, includeCreators: Bool? = nil, requestOptions: RequestOptions? = nil) async throws -> ReferenceRead {
        return try await httpClient.performRequest(
            method: .get,
            path: "/references/\(referenceId)",
            queryParams: [
                "include_creators": includeCreators.map { .bool($0) }
            ],
            requestOptions: requestOptions,
            responseType: ReferenceRead.self
        )
    }

    /// Update reference metadata and status (used by video processor)
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func updateReference(referenceId: String, request: [String: JSONValue], requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .patch,
            path: "/references/\(referenceId)",
            body: request,
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}