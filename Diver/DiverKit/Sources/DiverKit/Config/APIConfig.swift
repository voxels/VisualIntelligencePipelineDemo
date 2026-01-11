//
//  APIConfig.swift
//  Diver
//
//  Configuration for API client
//

import Foundation

public enum APIConfig {
    /// Base URL for the API (Know Maps backend)
    public static var baseURL: String {
        return ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api-ewrihjjgiq-uc.a.run.app"
    }

    /// Default timeout for API requests
    public static let defaultTimeout: TimeInterval = 60

    /// Enable verbose logging
    public static let enableLogging: Bool = false
}
