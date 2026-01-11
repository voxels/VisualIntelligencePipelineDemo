
import Foundation
import WeatherKit
import CoreLocation
import DiverShared

@available(iOS 16.0, macOS 13.0, *)
public actor WeatherEnrichmentService {
    private let weatherService = WeatherService.shared
    
    public init() {}
    
    public func fetchWeather(for location: CLLocation) async -> WeatherContext? {
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather
            
            return WeatherContext(
                condition: current.condition.description,
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                symbolName: current.symbolName
            )
        } catch {
            print("Failed to fetch weather: \(error)")
            return nil
        }
    }
}


