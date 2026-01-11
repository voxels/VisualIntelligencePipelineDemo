import Foundation

public final class ItemsClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    public func listItems(limit: Int? = nil, offset: Int? = nil, intent: String? = nil, modality: String? = nil, format: String? = nil, audienceLevel: String? = nil, language: String? = nil, sourceType: String? = nil, requestOptions: RequestOptions? = nil) async throws -> [ItemRead] {
        return try await httpClient.performRequest(
            method: .get,
            path: "/items",
            queryParams: [
                "limit": limit.map { .int($0) }, 
                "offset": offset.map { .int($0) }, 
                "intent": intent.map { .string($0) }, 
                "modality": modality.map { .string($0) }, 
                "format": format.map { .string($0) }, 
                "audience_level": audienceLevel.map { .string($0) }, 
                "language": language.map { .string($0) }, 
                "source_type": sourceType.map { .string($0) }
            ],
            requestOptions: requestOptions,
            responseType: [ItemRead].self
        )
    }

    /// Create a new item.
    /// 
    /// Behavior:
    /// - If `reference_id` is provided in the payload, link the created Item to that Reference.
    /// - User is authenticated via JWT token and automatically associated with the item.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func createItem(request: Requests.ItemCreate, requestOptions: RequestOptions? = nil) async throws -> ItemRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/items",
            body: request,
            requestOptions: requestOptions,
            responseType: ItemRead.self
        )
    }

    /// Get item by ID with optional media and reference details.
    ///
    /// - Parameter includeReferences: Include full reference objects with creators
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getItem(itemId: String, includeMedia: Bool? = nil, includeReferences: Bool? = nil, requestOptions: RequestOptions? = nil) async throws -> ItemReadWithRelations {
        return try await httpClient.performRequest(
            method: .get,
            path: "/items/\(itemId)",
            queryParams: [
                "include_media": includeMedia.map { .bool($0) }, 
                "include_references": includeReferences.map { .bool($0) }
            ],
            requestOptions: requestOptions,
            responseType: ItemReadWithRelations.self
        )
    }

    /// Update an existing item with analysis results
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func updateItem(itemId: String, userId: String? = nil, request: [String: JSONValue], requestOptions: RequestOptions? = nil) async throws -> ItemRead {
        return try await httpClient.performRequest(
            method: .put,
            path: "/items/\(itemId)",
            headers: [
                "X-User-Id": userId
            ],
            body: request,
            requestOptions: requestOptions,
            responseType: ItemRead.self
        )
    }

    public func deleteItem(itemId: String, requestOptions: RequestOptions? = nil) async throws -> Void {
        return try await httpClient.performRequest(
            method: .delete,
            path: "/items/\(itemId)",
            requestOptions: requestOptions
        )
    }

    /// Create association between an existing Item and Reference.
    /// 
    /// Idempotent: if the link already exists, returns 200 with no change.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func linkItemReference(itemId: String, referenceId: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/items/\(itemId)/references/\(referenceId)",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    /// Trigger Dagster pipeline to process a TikTok item
    /// 
    /// This endpoint replaces the old Huey queue system with Dagster orchestration.
    /// It will:
    /// 1. Extract TikTok metadata
    /// 2. Upload media to S3
    /// 3. Run Gemini analysis
    /// 4. Classify with DSPy
    /// 5. Search for references (Spotify/OpenLibrary)
    /// 6. Create references with DSPy
    /// 
    /// Returns:
    ///     dict: Contains run_id, item_id, job_uuid, and status
    ///
    /// - Parameter tiktokUrl: TikTok URL to process
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func processItem(itemId: String, tiktokUrl: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/items/\(itemId)/process",
            queryParams: [
                "tiktok_url": .string(tiktokUrl)
            ],
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    /// Get status of a Dagster pipeline run
    /// 
    /// Returns detailed information about the pipeline execution including:
    /// - Run status (QUEUED, STARTED, SUCCESS, FAILURE, etc.)
    /// - Steps succeeded/failed
    /// - Materializations count
    /// - Start/end times
    ///
    /// - Parameter runId: Dagster run ID
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getProcessStatus(itemId: String, runId: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .get,
            path: "/items/\(itemId)/process/status",
            queryParams: [
                "run_id": .string(runId)
            ],
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}