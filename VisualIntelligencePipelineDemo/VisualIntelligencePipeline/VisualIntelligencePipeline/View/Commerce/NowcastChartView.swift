//
//  NowcastChartView.swift
//  VisualIntelligencePipeline
//
//  Displays price trajectory nowcast using Swift Charts.
//  Shows historical data points and projected trend direction.
//

import SwiftUI
import Charts
import DiverShared

/// Price trajectory chart with nowcast projection.
struct NowcastChartView: View {
    let trajectory: PriceTrajectory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: trendIcon)
                    .foregroundStyle(trendColor)
                    .symbolEffect(.pulse, isActive: trajectory.projectedDirection != .stable)
                
                Text("Price Trend")
                    .font(.headline)
                
                Spacer()
                
                Text(trendLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trendColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(trendColor.opacity(0.12), in: Capsule())
            }
            
            if trajectory.dataPoints.isEmpty {
                ContentUnavailableView(
                    "No Pricing Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Price data will appear when available.")
                )
                .frame(height: 160)
            } else {
                Chart {
                    // Historical data points
                    ForEach(trajectory.dataPoints, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", NSDecimalNumber(decimal: point.value).doubleValue)
                        )
                        .foregroundStyle(.primary)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Price", NSDecimalNumber(decimal: point.value).doubleValue)
                        )
                        .foregroundStyle(.primary)
                        .symbolSize(20)
                    }
                    
                    // Trend indicator arrow rule
                    if let lastPoint = trajectory.dataPoints.last {
                        let lastValue = NSDecimalNumber(decimal: lastPoint.value).doubleValue
                        RuleMark(y: .value("Current", lastValue))
                            .foregroundStyle(trendColor.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(v, specifier: "%.0f")")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
            
            // Confidence indicator
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.caption)
                Text("Confidence: \(Int(trajectory.confidenceInterval * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var trendIcon: String {
        switch trajectory.projectedDirection {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    private var trendLabel: String {
        switch trajectory.projectedDirection {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .stable: return "Stable"
        }
    }
    
    private var trendColor: Color {
        switch trajectory.projectedDirection {
        case .rising: return .red
        case .falling: return .green
        case .stable: return .blue
        }
    }
}

#Preview {
    NowcastChartView(
        trajectory: PriceTrajectory(
            commodityID: "coffee",
            dataPoints: (0..<6).map { i in
                PriceDataPoint(
                    date: Calendar.current.date(byAdding: .month, value: -i, to: .now)!,
                    value: Decimal(95 + Int.random(in: -10...10))
                )
            },
            projectedDirection: .rising,
            confidenceInterval: 0.72,
            horizonDays: 14
        )
    )
    .padding()
}
