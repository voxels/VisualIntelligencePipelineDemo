import Foundation

public final class InputsClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// List all inputs with pagination, optionally including linked items.
    ///
    /// - Parameter includeItems: Include linked items in response
    /// - Parameter inputType: Filter by input type (e.g., tiktok)
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func listInputs(includeItems: Bool? = nil, limit: Int? = nil, offset: Int? = nil, inputType: String? = nil, requestOptions: RequestOptions? = nil) async throws -> [InputRead] {
        return try await httpClient.performRequest(
            method: .get,
            path: "/inputs",
            queryParams: [
                "include_items": includeItems.map { .bool($0) }, 
                "limit": limit.map { .int($0) }, 
                "offset": offset.map { .int($0) }, 
                "input_type": inputType.map { .string($0) }
            ],
            requestOptions: requestOptions,
            responseType: [InputRead].self
        )
    }

    /// Create a new Input and enqueue it for processing.
    /// 
    /// Handles deduplication:
    /// - If source URL already exists, links user to existing item and returns original input
    /// - If new URL, creates input and enqueues for processing
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func createInput(request: Requests.InputCreate, requestOptions: RequestOptions? = nil) async throws -> InputRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/inputs",
            body: request,
            requestOptions: requestOptions,
            responseType: InputRead.self
        )
    }

    /// Get a specific input by ID with all related data eagerly loaded.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getInput(inputId: String, requestOptions: RequestOptions? = nil) async throws -> InputRead {
        return try await httpClient.performRequest(
            method: .get,
            path: "/inputs/\(inputId)",
            requestOptions: requestOptions,
            responseType: InputRead.self
        )
    }

    public func deleteInput(inputId: String, requestOptions: RequestOptions? = nil) async throws -> Void {
        return try await httpClient.performRequest(
            method: .delete,
            path: "/inputs/\(inputId)",
            requestOptions: requestOptions
        )
    }

    /// Trigger specific processing stages for an input.
    /// 
    /// Stages:
    /// - media: Process video/images only
    /// - classification: Classify item (requires media)
    /// - research: Extract and create references (requires classification)
    /// - full: Complete pipeline (media → classification → research)
    ///
    /// - Parameter stage: Processing stage: 'media', 'classification', 'research', or 'full'
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func triggerProcessing(inputId: String, stage: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .patch,
            path: "/inputs/\(inputId)/process",
            queryParams: [
                "stage": .string(stage)
            ],
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}