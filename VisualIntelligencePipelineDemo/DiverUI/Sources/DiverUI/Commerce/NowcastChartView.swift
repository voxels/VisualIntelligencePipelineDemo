//
//  NowcastChartView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import Charts
import DiverShared

public struct NowcastChartView: View {
    public let trajectory: PriceTrajectory
    public init(trajectory: PriceTrajectory) { self.trajectory = trajectory }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: trendIcon).foregroundStyle(trendColor)
                    .symbolEffect(.pulse, isActive: trajectory.projectedDirection != .stable)
                Text("Price Trend").font(.headline)
                Spacer()
                Text(trendLabel)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(trendColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(trendColor.opacity(0.12), in: Capsule())
            }
            if trajectory.dataPoints.isEmpty {
                ContentUnavailableView(
                    "No Pricing Data", systemImage: "chart.bar.xaxis",
                    description: Text("Price data will appear when available.")
                ).frame(height: 160)
            } else {
                Chart {
                    ForEach(trajectory.dataPoints, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", NSDecimalNumber(decimal: point.value).doubleValue)
                        ).foregroundStyle(.primary).interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Price", NSDecimalNumber(decimal: point.value).doubleValue)
                        ).foregroundStyle(.primary).symbolSize(20)
                    }
                    if let last = trajectory.dataPoints.last {
                        let v = NSDecimalNumber(decimal: last.value).doubleValue
                        RuleMark(y: .value("Current", v))
                            .foregroundStyle(trendColor.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(v, specifier: "%.0f")").font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.caption)
                Text("Confidence: \(Int(trajectory.confidenceInterval * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var trendIcon: String {
        switch trajectory.projectedDirection {
        case .rising: "arrow.up.right"; case .falling: "arrow.down.right"; case .stable: "arrow.right"
        }
    }
    private var trendLabel: String {
        switch trajectory.projectedDirection {
        case .rising: "Rising"; case .falling: "Falling"; case .stable: "Stable"
        }
    }
    private var trendColor: Color {
        switch trajectory.projectedDirection {
        case .rising: .red; case .falling: .green; case .stable: .blue
        }
    }
}
