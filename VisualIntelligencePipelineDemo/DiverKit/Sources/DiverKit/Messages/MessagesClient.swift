import Foundation

public final class MessagesClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    /// Get a message with typed message_data for schema generation.
    /// 
    /// This endpoint exists primarily to expose message data types to OpenAPI/Fern.
    /// The discriminated union automatically parses based on message_type field.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getTypedMessage(jobUuid: String, messageId: String, requestOptions: RequestOptions? = nil) async throws -> GetTypedMessageMessagesJobUuidTypedMessageIdGetResponse {
        return try await httpClient.performRequest(
            method: .get,
            path: "/messages/\(jobUuid)/typed/\(messageId)",
            requestOptions: requestOptions,
            responseType: GetTypedMessageMessagesJobUuidTypedMessageIdGetResponse.self
        )
    }

    /// Get messages for a job/conversation.
    /// 
    /// Authorization: User must have access to the item (via UserItem).
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func listMessages(jobUuid: String, limit: Int? = nil, cursor: String? = nil, requestOptions: RequestOptions? = nil) async throws -> MessageListResponse {
        return try await httpClient.performRequest(
            method: .get,
            path: "/messages/\(jobUuid)",
            queryParams: [
                "limit": limit.map { .int($0) }, 
                "cursor": cursor.map { .string($0) }
            ],
            requestOptions: requestOptions,
            responseType: MessageListResponse.self
        )
    }

    /// Create a new message in a conversation.
    /// 
    /// Authorization:
    /// - Users: Must be authenticated via JWT or API key
    /// - Service accounts are identified by account_type field
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func createMessage(request: Requests.MessageCreate, requestOptions: RequestOptions? = nil) async throws -> MessageRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/messages",
            body: request,
            requestOptions: requestOptions,
            responseType: MessageRead.self
        )
    }

    /// Get all users and agents who have participated in this conversation.
    /// 
    /// Authorization: User must have access to the conversation.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getConversationParticipants(jobUuid: String, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .get,
            path: "/messages/\(jobUuid)/participants",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }
}