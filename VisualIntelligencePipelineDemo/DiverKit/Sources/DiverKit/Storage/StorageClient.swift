import Foundation

public final class StorageClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// Generate presigned URL for S3 operations (client uploads only)
    /// 
    /// Args:
    ///     s3_key: Full S3 key (e.g., "jobs/{uuid}/media/video.mp4")
    ///     operation: "upload" or "download"
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func generatePresignedUrl(s3Key: String, operation: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/storage/presigned-url",
            queryParams: [
                "s3_key": .string(s3Key), 
                "operation": .string(operation)
            ],
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    /// List all files for a specific job
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func listJobFiles(jobUuid: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .get,
            path: "/storage/jobs/\(jobUuid)/files",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}