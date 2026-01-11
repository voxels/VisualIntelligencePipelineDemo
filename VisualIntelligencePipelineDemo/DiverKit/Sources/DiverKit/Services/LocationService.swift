import Foundation
import CoreLocation
import DiverShared

/// Protocol defining the interface for location services to allow for mocking in tests.
public protocol LocationProvider: AnyObject, Sendable {
    func getCurrentLocation() async -> CLLocation?
}

/// Service responsible for fetching the current GPS location
public final class LocationService: NSObject, LocationProvider, @unchecked Sendable {
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
            locationManager.requestWhenInUseAuthorization()
            return nil
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
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiverLogger.pipeline.error("Location lookup failed: \(error.localizedDescription)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Handle authorization changes if necessary
    }
}
