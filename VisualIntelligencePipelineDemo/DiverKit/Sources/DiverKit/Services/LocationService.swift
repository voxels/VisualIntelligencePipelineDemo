import Foundation
import CoreLocation
import DiverShared

/// Protocol defining the interface for location services to allow for mocking in tests.
public protocol LocationProvider: AnyObject, Sendable {
    func getCurrentLocation() async -> CLLocation?
}

/// Service responsible for fetching the current GPS location.
@MainActor
public final class LocationService: NSObject, LocationProvider {
    private let locationManager: CLLocationManager
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    
    public override init() {
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    /// Requests the current location.
    public func getCurrentLocation() async -> CLLocation? {
        // Prevent concurrent requests to avoid leaking continuations
        if locationContinuation != nil {
            return nil
        }
        
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.locationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
                // The delegate method locationManagerDidChangeAuthorization will handle the state change
                // and we'll trigger requestLocation() there if authorized.
            }
        case .restricted, .denied:
            return nil
        case .authorizedAlways, .authorizedWhenInUse:
            return await withCheckedContinuation { continuation in
                self.locationContinuation = continuation
                locationManager.requestLocation()
            }
        @unknown default:
            return nil
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }
    
    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiverLogger.pipeline.error("Location lookup failed: \(error.localizedDescription)")
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
    
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        let isAuthorized = status == .authorizedAlways || status == .authorizedWhenInUse
        #else
        let isAuthorized = status == .authorizedAlways
        #endif

        Task { @MainActor in
            if isAuthorized {
                // Only trigger if we are waiting for a continuation
                if self.locationContinuation != nil {
                    self.locationManager.requestLocation()
                }
            } else if status == .denied || status == .restricted {
                self.locationContinuation?.resume(returning: nil)
                self.locationContinuation = nil
            }
        }
    }
}
