
import Foundation
import CoreLocation
import DiverShared

@available(iOS 16.0, macOS 13.0, *)
public actor ContextEnrichmentCoordinator {
    private let weatherService: WeatherEnrichmentService
    
    // Foursquare/Place service would be injected here in a real implementation
    // For now, we assume it's handled separately or passed in
    
    public init() {
        self.weatherService = WeatherEnrichmentService()
    }
    
    public func enrich(location: CLLocation?) async -> ContextSnapshot {
        let weather = await fetchWeather(for: location)
        
        // In a real scenario, we might also await Foursquare/Place data here
        // For now, we return what we found
        
        return ContextSnapshot(
            weather: weather,
            activity: nil, // Activity tracking removed
            place: nil, // Placeholder for Foursquare integration
            timestamp: Date()
        )
    }
    
    private func fetchWeather(for location: CLLocation?) async -> WeatherContext? {
        guard let location = location else { return nil }
        return await weatherService.fetchWeather(for: location)
    }

}


