//  AuthManager.swift
//  Diver
//
//  Apple Sign-In authentication wrapper using DiverKit.
//  Migrated from email/password to Apple Sign-In only.
//

import Foundation
import Combine
import AuthenticationServices

/// Authentication manager that wraps DiverKit's AppleAuthenticationService.
/// Provides a simplified interface for the app's authentication needs.
@MainActor
public final class AuthManager: ObservableObject {
    public static let shared = AuthManager()

    // MARK: - Published Properties

    @Published public var currentUser: User?
    @Published public var authState: AuthenticationState = .unauthenticated
    @Published public var errorMessage: String?
    public let appleAuth: AppleAuthenticationService

    // MARK: - Private Properties

    private let keychain: KeychainService
    private var cancellables = Set<AnyCancellable>()

    /// API client with current auth token
    public var apiClient: ApiClient {
        ApiClient(
            baseURL: APIConfig.baseURL,
            token: appleAuth.retrieveAccessToken()
        )
    }

    // MARK: - Computed Properties

    public var isAuthenticated: Bool {
        authState == .authenticated
    }

    public var token: String? {
        appleAuth.retrieveAccessToken()
    }

    // MARK: - Initialization

    private init() {
        // Use default DiverKit config (Know Maps backend)
        self.appleAuth = AppleAuthenticationService()
        self.keychain = KeychainService(
            service: KeychainService.ServiceIdentifier.diverKit,
            accessGroup: "group.com.secretatomics.diver.shared"
        )

        setupBindings()
        checkExistingAuth()
    }

    // MARK: - Setup

    private func setupBindings() {
        appleAuth.$signInErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    private func checkExistingAuth() {
        if appleAuth.isSignedIn() {
            authState = .authenticated
            loadStoredUser()
        }
    }

    // MARK: - Public API
    
    public func logOut() {
        appleAuth.signOut()
        authState = .unauthenticated
        currentUser = nil
    }
    
    public func signIn() async throws {
//        appleAuth.signIn()
        if let _ = await appleAuth.getValidAccessTokenAsync() {
            authState = .authenticated
            loadOrCreateUser(appleUserId: appleAuth.getValidAccessToken()!)
        }
        else {
            authState = .unauthenticated
            throw NSError(domain: "Sign in failed", code: 0, userInfo: nil)
        }
    }

    public func refreshCurrentUser() async {
        if let _ = await appleAuth.getValidAccessTokenAsync() {
            await refreshUserFromAPI()
        } else {
            authState = .unauthenticated
        }
    }

    // MARK: - User Management

    private func loadOrCreateUser(appleUserId: String) {
        // First try to load stored user
        if let user = loadStoredUser() {
            currentUser = user
            return
        }

        // If no stored user, create a placeholder from Apple ID
        // The full user profile can be fetched from API later
        Task {
            await refreshUserFromAPI()
        }
    }

    @discardableResult
    private func loadStoredUser() -> User? {
        guard let data = keychain.retrieve(key: "current_user") else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let user = try decoder.decode(User.self, from: data)
            currentUser = user
            return user
        } catch {
            print("❌ Failed to decode stored user: \(error)")
            return nil
        }
    }

    private func storeUser(_ user: User) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(user)
            try keychain.store(key: "current_user", data: data)
            currentUser = user
        } catch {
            print("❌ Failed to store user: \(error)")
        }
    }

    private func clearStoredUser() {
        keychain.delete(key: "current_user")
    }

    private func refreshUserFromAPI() async {
        do {
            let user = try await apiClient.auth.usersCurrentUser()
            storeUser(user)
            #if DEBUG
            print("✅ User refreshed from API: \(user.email)")
            #endif
        } catch {
            // Not a critical error - continue with cached user silently
            // Backend may be unavailable (503) which is expected during development
            #if DEBUG
            print("ℹ️ Using cached user (API unavailable)")
            #endif
        }
    }

    // MARK: - Validation

    /// Validates the current authentication state by ensuring a valid Apple token exists.
    /// Updates `authState` accordingly.
    public func validateAuthentication() async {
        if let _ = await appleAuth.getValidAccessTokenAsync() {
            if authState != .authenticated {
                authState = .authenticated
            }
        } else {
            if authState != .unauthenticated {
                authState = .unauthenticated
            }
        }
    }
}
