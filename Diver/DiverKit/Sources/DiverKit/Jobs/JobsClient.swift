import Foundation

public final class JobsClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// Stream real-time job progress via SSE.
    /// 
    /// Client connects and receives log events as they happen.
    /// Connection stays open until client disconnects.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func streamJobProgress(jobUuid: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .get,
            path: "/jobs/\(jobUuid)/stream",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}