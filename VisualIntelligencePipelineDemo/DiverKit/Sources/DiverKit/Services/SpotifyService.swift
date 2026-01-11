//
//  SpotifyService.swift
//  Diver
//
//  Spotify OAuth and playback service
//

import SwiftUI
import SpotifyWebAPI
import Combine
import Security
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class DiverSpotify: ObservableObject {
    
    static let shared = DiverSpotify()
    
    private static let clientId = "484df967b7cf4d92bbd8c51842012f8f"
    
    /// The URL that Spotify will redirect to after authorization
    let loginCallbackURL = URL(string: "diver://spotify-callback")!
    
    /// State parameter for OAuth security
    var authorizationState = ""
    
    /// Code verifier for PKCE
    var codeVerifier = ""
    
    @Published var isAuthorized = false
    @Published var isRetrievingTokens = false
    @Published var currentlyPlayingTrackURI: String? = nil
    @Published var isPlaying = false
    
    /// Service name for keychain storage
    private let keychainService = "com.diver.spotify"
    
    /// Key for storing authorization manager in keychain
    private let authorizationManagerKey = "spotifyAuthorizationManager"
    
    /// The SpotifyAPI instance  
    let api = SpotifyAPI(
        authorizationManager: AuthorizationCodeFlowPKCEManager(
            clientId: DiverSpotify.clientId
        )
    )
    
    var cancellables: Set<AnyCancellable> = []
    
    private init() {
        print("🎵 Initializing DiverSpotify with clientId: \(DiverSpotify.clientId)")
        
        // IMPORTANT: Subscribe to authorization changes BEFORE loading from keychain
        self.api.authorizationManagerDidChange
            .receive(on: RunLoop.main)
            .sink(receiveValue: authorizationManagerDidChange)
            .store(in: &cancellables)
        
        self.api.authorizationManagerDidDeauthorize
            .receive(on: RunLoop.main)
            .sink(receiveValue: authorizationManagerDidDeauthorize)
            .store(in: &cancellables)
        
        // Try to load saved authorization from keychain
        loadAuthorizationFromKeychain()
    }
    
    func authorize() {
        // Generate new values for each authorization request
        self.codeVerifier = String.randomURLSafe(length: 128)
        self.authorizationState = String.randomURLSafe(length: 128)
        
        print("🔑 Generated codeVerifier: \(self.codeVerifier)")
        print("🔑 Generated authorizationState: \(self.authorizationState)")
        
        let url = self.api.authorizationManager.makeAuthorizationURL(
            redirectURI: self.loginCallbackURL,
            codeChallenge: String.makeCodeChallenge(codeVerifier: self.codeVerifier),
            state: self.authorizationState,
            scopes: [
                .playlistReadPrivate,
                .playlistReadCollaborative,
                .userReadPrivate,
                .userReadPlaybackState,
                .userModifyPlaybackState,
                .streaming
            ]
        )!
        
        print("🔗 Opening authorization URL: \(url)")
        
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
    
    func authorizationManagerDidChange() {
        self.isAuthorized = self.api.authorizationManager.isAuthorized()
        print("DiverSpotify.authorizationManagerDidChange: isAuthorized: \(self.isAuthorized)")
        
        // Save authorization to keychain whenever it changes
        saveAuthorizationToKeychain()
        
        // Notify views that authorization changed
        if self.isAuthorized {
            NotificationCenter.default.post(name: NSNotification.Name("SpotifyAuthorized"), object: nil)
        }
    }
    
    func authorizationManagerDidDeauthorize() {
        self.isAuthorized = false
        
        // Remove authorization from keychain when deauthorized
        removeAuthorizationFromKeychain()
    }
    
    func handleURL(_ url: URL) {
        guard url.scheme == self.loginCallbackURL.scheme else {
            print("not handling URL: unexpected scheme: '\(url)'")
            return
        }
        
        print("🔗 Spotify redirect URL: \(url)")
        print("🔑 Using codeVerifier: \(self.codeVerifier)")
        print("🔑 Using authorizationState: \(self.authorizationState)")
        
        self.isRetrievingTokens = true
        
        self.api.authorizationManager.requestAccessAndRefreshTokens(
            redirectURIWithQuery: url,
            codeVerifier: self.codeVerifier,
            state: self.authorizationState
        )
        .receive(on: RunLoop.main)
        .sink(
            receiveCompletion: { completion in
                self.isRetrievingTokens = false
                
                switch completion {
                case .finished:
                    print("✅ Token exchange completed successfully")
                case .failure(let error):
                    print("❌ Token exchange failed: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    if let spotifyError = error as? SpotifyAuthorizationError {
                        print("❌ Spotify error: \(spotifyError)")
                    }
                }
            },
            receiveValue: { _ in
                print("✅ Successfully retrieved access and refresh tokens")
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: - Keychain Persistence
    
    private func loadAuthorizationFromKeychain() {
        guard let authManagerData = getKeychainData(key: authorizationManagerKey) else {
            print("🎵 No saved Spotify authorization found")
            return
        }
        
        do {
            let authorizationManager = try JSONDecoder().decode(
                AuthorizationCodeFlowPKCEManager.self,
                from: authManagerData
            )
            print("🎵 Loaded Spotify authorization from keychain")
            
            // This will trigger authorizationManagerDidChange
            self.api.authorizationManager = authorizationManager
            
        } catch {
            print("❌ Failed to decode Spotify authorization: \(error)")
            // Remove corrupted data
            _ = removeKeychainData(key: authorizationManagerKey)
        }
    }
    
    private func saveAuthorizationToKeychain() {
        do {
            let authManagerData = try JSONEncoder().encode(self.api.authorizationManager)
            if setKeychainData(key: authorizationManagerKey, data: authManagerData) {
                print("🎵 Saved Spotify authorization to keychain")
            } else {
                print("❌ Failed to save Spotify authorization to keychain")
            }
        } catch {
            print("❌ Failed to encode Spotify authorization: \(error)")
        }
    }
    
    private func removeAuthorizationFromKeychain() {
        if removeKeychainData(key: authorizationManagerKey) {
            print("🎵 Removed Spotify authorization from keychain")
        } else {
            print("❌ Failed to remove Spotify authorization from keychain")
        }
    }
    
    // MARK: - Native Keychain Helpers
    
    private func setKeychainData(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func getKeychainData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    
    private func removeKeychainData(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Playback Control
    
    func playTrack(track: Track, completion: @escaping (Bool) -> Void) {
        guard isAuthorized else {
            print("❌ Not authorized to play tracks")
            completion(false)
            return
        }
        
        guard let trackURI = track.uri else {
            print("❌ Track missing URI")
            completion(false)
            return
        }
        
        let playbackRequest: PlaybackRequest
        
        if let albumURI = track.album?.uri {
            // Play the track in the context of its album
            playbackRequest = PlaybackRequest(
                context: .contextURI(albumURI),
                offset: .uri(trackURI)
            )
        } else {
            // Play just the track
            playbackRequest = PlaybackRequest(trackURI)
        }
        
        // Update state immediately - optimistic update
        self.currentlyPlayingTrackURI = trackURI
        self.isPlaying = true
        
        // Use getAvailableDeviceThenPlay for automatic device selection
        api.getAvailableDeviceThenPlay(playbackRequest)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completionResult in
                    switch completionResult {
                    case .finished:
                        print("✅ Playback started successfully")
                        // Keep the optimistic state
                        Task { @MainActor in
                            ToastManager.shared.success("Playing track: \(track.name)")
                        }
                        completion(true)
                    case .failure(let error):
                        print("❌ Failed to start playback: \(error)")
                        // Reset state on failure
                        self.currentlyPlayingTrackURI = nil
                        self.isPlaying = false
                        
                        // Show user-friendly error message
                        Task { @MainActor in
                            let errorMessage = self.getUserFriendlyErrorMessage(error)
                            ToastManager.shared.error("Failed to start playback", message: errorMessage)
                        }
                        completion(false)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Pause Playback
    
    func pausePlayback(completion: @escaping (Bool) -> Void) {
        guard isAuthorized else {
            print("❌ Not authorized to pause playback")
            completion(false)
            return
        }
        
        print("⏸️ Pausing playback")
        
        // Update state immediately
        self.isPlaying = false
        
        api.pausePlayback()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completionResult in
                    switch completionResult {
                    case .finished:
                        print("✅ Playback paused successfully")
                        Task { @MainActor in
                            ToastManager.shared.info("Playback paused")
                        }
                        completion(true)
                    case .failure(let error):
                        print("❌ Failed to pause playback: \(error)")
                        // Reset state on failure
                        self.isPlaying = true
                        Task { @MainActor in
                            ToastManager.shared.error("Failed to pause playback")
                        }
                        completion(false)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Error Handling
    
    private func getUserFriendlyErrorMessage(_ error: Error) -> String {
        if let spotifyError = error as? SpotifyGeneralError {
            switch spotifyError {
            case .other(let reason, let localizedDescription):
                if reason == "no active or available devices" {
                    return "No devices available. Try opening the Spotify app on one of your devices."
                }
                return localizedDescription
            default:
                return spotifyError.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    // MARK: - Logout
    
    func logout() {
        print("🎵 Logging out from Spotify")
        
        // Deauthorize the API
        api.authorizationManager.deauthorize()
        
        // Clear any stored state
        isAuthorized = false
        currentlyPlayingTrackURI = nil
        isPlaying = false
        
        // Remove from keychain (this will be called automatically by authorizationManagerDidDeauthorize)
    }
}

// MARK: - SpotifyAPI Extensions

extension SpotifyAPI where AuthorizationManager: SpotifyScopeAuthorizationManager {

    /**
     Makes a call to `availableDevices()`  and plays the content on the active
     device if one exists. Else, plays content on the first available device.
     
     See [Using the Player Endpoints][1].

     - Parameter playbackRequest: A request to play content.

     [1]: https://peter-schorn.github.io/SpotifyAPI/documentation/spotifywebapi/using-the-player-endpoints
     */
    func getAvailableDeviceThenPlay(
        _ playbackRequest: PlaybackRequest
    ) -> AnyPublisher<Void, Error> {
        
        return self.availableDevices().flatMap {
            devices -> AnyPublisher<Void, Error> in
    
            // A device must have an id and must not be restricted in order to
            // accept web API commands.
            let usableDevices = devices.filter { device in
                !device.isRestricted && device.id != nil
            }

            // If there is an active device, then it's usually a good idea to
            // use that one. For example, if content is already playing, then it
            // will be playing on the active device. If not, then just use the
            // first available device.
            let device = usableDevices.first(where: \.isActive)
                    ?? usableDevices.first
            
            if let deviceId = device?.id {
                return self.play(playbackRequest, deviceId: deviceId)
            }
            else {
                return SpotifyGeneralError.other(
                    "no active or available devices",
                    localizedDescription:
                    "There are no devices available to play content on. " +
                    "Try opening the Spotify app on one of your devices."
                )
                .anyFailingPublisher()
            }
            
        }
        .eraseToAnyPublisher()
        
    }

}
