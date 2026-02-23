import SwiftUI
import SwiftData
import DiverShared

/// A specialized profile view for displaying passive environmental and activity contexts 
/// gathered during a capture, such as weather conditions and CoreMotion activity states.
struct EnvironmentProfileView: View {
    let item: ProcessedItem
    
    var body: some View {
        VStack(spacing: 16) {
            if item.weatherContext != nil || item.activityContext != nil {
                HStack(alignment: .top, spacing: 16) {
                    if let weather = item.weatherContext {
                        WeatherContextView(context: weather)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if let activity = item.activityContext {
                        ActivityContextView(context: activity)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Weather Context
struct WeatherContextView: View {
    let context: WeatherContext
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(context.condition)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(context.temperatureCelsius))°C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Activity Context
struct ActivityContextView: View {
    let context: ActivityContext
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForActivity(context.type))
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(context.type.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(context.confidence.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func iconForActivity(_ type: String) -> String {
        switch type.lowercased() {
        case "walking": return "figure.walk"
        case "running": return "figure.run"
        case "automotive", "driving": return "car.fill"
        case "cycling": return "bicycle"
        case "stationary": return "figure.stand"
        default: return "figure.mixed.cardio"
        }
    }
}
