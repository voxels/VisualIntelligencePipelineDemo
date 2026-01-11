import Combine
import Foundation

@MainActor
public final class AppleAuthenticationService: ObservableObject {
    @Published public private(set) var signInErrorMessage: String?

    private let keychain: KeychainService

    public init(
        keychain: KeychainService = KeychainService(
            service: KeychainService.ServiceIdentifier.diverKit,
            accessGroup: "group.com.secretatomics.diver.shared"
        )
    ) {
        self.keychain = keychain
    }

    public func isSignedIn() -> Bool {
        getValidAccessToken() != nil
    }

    public func signOut() {
        keychain.delete(key: KeychainService.Keys.accessToken)
        keychain.delete(key: KeychainService.Keys.refreshToken)
        keychain.delete(key: KeychainService.Keys.accessTokenExpiry)
        keychain.delete(key: KeychainService.Keys.appleUserId)
    }

    public func retrieveAccessToken() -> String? {
        keychain.retrieveString(key: KeychainService.Keys.accessToken)
    }

    public func storeAccessToken(_ token: String) {
        do {
            try keychain.store(key: KeychainService.Keys.accessToken, value: token)
        } catch {
            signInErrorMessage = "Failed to store access token"
        }
    }

    public func getValidAccessToken() -> String? {
        guard let token = retrieveAccessToken() else { return nil }
        return TokenValidator.isTokenExpired(token) ? nil : token
    }

    public func getValidAccessTokenAsync() async -> String? {
        getValidAccessToken()
    }
}

