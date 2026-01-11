import Foundation

public final class MediaClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// List media entries with optional filters
    ///
    /// - Parameter itemId: Filter by item ID
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func listMedia(itemId: String? = nil, limit: Int? = nil, offset: Int? = nil, requestOptions: RequestOptions? = nil) async throws -> [MediaRead] {
        return try await httpClient.performRequest(
            method: .get,
            path: "/media",
            queryParams: [
                "item_id": itemId.map { .string($0) }, 
                "limit": limit.map { .int($0) }, 
                "offset": offset.map { .int($0) }
            ],
            requestOptions: requestOptions,
            responseType: [MediaRead].self
        )
    }

    /// Create a new media entry
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func createMedia(request: Requests.MediaCreate, requestOptions: RequestOptions? = nil) async throws -> MediaRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/media",
            body: request,
            requestOptions: requestOptions,
            responseType: MediaRead.self
        )
    }

    /// Get a specific media entry
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getMedia(mediaId: String, requestOptions: RequestOptions? = nil) async throws -> MediaRead {
        return try await httpClient.performRequest(
            method: .get,
            path: "/media/\(mediaId)",
            requestOptions: requestOptions,
            responseType: MediaRead.self
        )
    }

    /// Delete a media entry
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func deleteMedia(mediaId: String, requestOptions: RequestOptions? = nil) async throws -> Void {
        return try await httpClient.performRequest(
            method: .delete,
            path: "/media/\(mediaId)",
            requestOptions: requestOptions
        )
    }

    /// Update a media entry
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func updateMedia(mediaId: String, request: Requests.MediaUpdate, requestOptions: RequestOptions? = nil) async throws -> MediaRead {
        return try await httpClient.performRequest(
            method: .patch,
            path: "/media/\(mediaId)",
            body: request,
            requestOptions: requestOptions,
            responseType: MediaRead.self
        )
    }
}