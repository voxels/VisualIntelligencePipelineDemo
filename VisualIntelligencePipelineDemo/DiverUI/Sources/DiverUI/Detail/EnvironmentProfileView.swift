//
//  EnvironmentProfileView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import DiverShared
import DiverKit

/// Specialized profile for passive environmental/activity context (weather + motion).
public struct EnvironmentProfileView: View {
    public let item: ProcessedItem
    public init(item: ProcessedItem) { self.item = item }

    public var body: some View {
        VStack(spacing: 16) {
            if item.weatherContext != nil || item.activityContext != nil {
                HStack(alignment: .top, spacing: 16) {
                    if let weather = item.weatherContext {
                        WeatherContextCard(context: weather).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let activity = item.activityContext {
                        ActivityContextCard(context: activity).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal).padding(.top, 8)
            }
        }
    }
}

// MARK: - Weather Card

public struct WeatherContextCard: View {
    public let context: WeatherContext
    public init(context: WeatherContext) { self.context = context }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.symbolName).symbolRenderingMode(.multicolor)
                .font(.title2).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.condition).font(.subheadline).fontWeight(.medium)
                Text("\(Int(context.temperatureCelsius))°C").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Activity Card

public struct ActivityContextCard: View {
    public let context: ActivityContext
    public init(context: ActivityContext) { self.context = context }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForActivity(context.type))
                .font(.title2).foregroundStyle(.orange).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.type.capitalized).font(.subheadline).fontWeight(.medium)
                Text(context.confidence.capitalized).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func iconForActivity(_ type: String) -> String {
        switch type.lowercased() {
        case "walking": "figure.walk"; case "running": "figure.run"
        case "automotive", "driving": "car.fill"; case "cycling": "bicycle"
        case "stationary": "figure.stand"; default: "figure.mixed.cardio"
        }
    }
}
