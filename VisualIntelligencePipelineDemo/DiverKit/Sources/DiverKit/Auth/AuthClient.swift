import Foundation

public final class AuthClient: Sendable {
    private let httpClient: HTTPClient

    init(config: ClientConfig) {
        self.httpClient = HTTPClient(config: config)
    }

    public func authJwtLogin(request: BodyAuthJwtLoginAuthJwtLoginPost, requestOptions: RequestOptions? = nil) async throws -> BearerResponse {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/jwt/login",
            body: request,
            requestOptions: requestOptions,
            responseType: BearerResponse.self
        )
    }

    public func authJwtLogout(requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/jwt/logout",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    public func registerRegister(request: Requests.UserCreate, requestOptions: RequestOptions? = nil) async throws -> UserRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/register",
            body: request,
            requestOptions: requestOptions,
            responseType: UserRead.self
        )
    }

    public func resetForgotPassword(request: Requests.BodyResetForgotPasswordAuthResetPasswordForgotPasswordPost, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/reset-password/forgot-password",
            body: request,
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    public func resetResetPassword(request: Requests.BodyResetResetPasswordAuthResetPasswordResetPasswordPost, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/reset-password/reset-password",
            body: request,
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    public func verifyRequestToken(request: Requests.BodyVerifyRequestTokenAuthVerifyRequestVerifyTokenPost, requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/verify/request-verify-token",
            body: request,
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    public func verifyVerify(request: Requests.BodyVerifyVerifyAuthVerifyVerifyPost, requestOptions: RequestOptions? = nil) async throws -> UserRead {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/verify/verify",
            body: request,
            requestOptions: requestOptions,
            responseType: UserRead.self
        )
    }

    /// Exchange API key for JWT token.
    /// Works for any user with an API key (not just services).
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func exchangeApiKeyForToken(requestOptions: RequestOptions? = nil) async throws -> JSONValue {
        return try await httpClient.performRequest(
            method: .post,
            path: "/auth/service/token",
            requestOptions: requestOptions,
            responseType: JSONValue.self
        )
    }

    public func usersCurrentUser(requestOptions: RequestOptions? = nil) async throws -> UserRead {
        return try await httpClient.performRequest(
            method: .get,
            path: "/users/me",
            requestOptions: requestOptions,
            responseType: UserRead.self
        )
    }

    public func usersPatchCurrentUser(request: UserUpdate, requestOptions: RequestOptions? = nil) async throws -> UserRead {
        return try await httpClient.performRequest(
            method: .patch,
            path: "/users/me",
            body: request,
            requestOptions: requestOptions,
            responseType: UserRead.self
        )
    }

    public func usersUser(id: String, requestOptions: RequestOptions? = nil) async throws -> UserRead {
        return try await httpClient.performRequest(
            method: .get,
            path: "/users/\(id)",
            requestOptions: requestOptions,
            responseType: UserRead.self
        )
    }

    public func usersDeleteUser(id: String, requestOptions: RequestOptions? = nil) async throws -> Void {
        return try await httpClient.performRequest(
            method: .delete,
            path: "/users/\(id)",
            requestOptions: requestOptions
        )
    }

    public func usersPatchUser(id: String, request: UserUpdate, requestOptions: RequestOptions? = nil) async throws -> UserRead {
        return try await httpClient.performRequest(
            method: .patch,
            path: "/users/\(id)",
            body: request,
            requestOptions: requestOptions,
            responseType: UserRead.self
        )
    }

    /// Get current user's profile.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getMyProfile(requestOptions: RequestOptions? = nil) async throws -> UserProfile {
        return try await httpClient.performRequest(
            method: .get,
            path: "/me/profile",
            requestOptions: requestOptions,
            responseType: UserProfile.self
        )
    }

    /// Get a user's public profile.
    ///
    /// - Parameter requestOptions: Additional options for configuring the request, such as custom headers or timeout settings.
    public func getUserProfile(userId: String, requestOptions: RequestOptions? = nil) async throws -> UserProfile {
        return try await httpClient.performRequest(
            method: .get,
            path: "/profiles/\(userId)",
            requestOptions: requestOptions,
            responseType: UserProfile.self
        )
    }
}