//
//  ScoreHistoryChartView.swift
//  VisualIntelligencePipeline
//
//  Time-series chart showing product score history using Swift Charts.
//  Displays ScoreSnapshot data points per strategy over time.
//

import SwiftUI
import Charts
import DiverKit
import DiverShared

/// Swift Charts time-series view for product score history.
struct ScoreHistoryChartView: View {
    let snapshots: [ScoreSnapshotData]
    let strategyID: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score History")
                .font(.headline)
            
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Scores will appear here after pipeline runs.")
                )
                .frame(height: 200)
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(colorForStrategy(strategyID))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    PointMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(colorForStrategy(strategyID))
                    .symbolSize(30)
                    
                    AreaMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [colorForStrategy(strategyID).opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func colorForStrategy(_ id: String) -> Color {
        switch id {
        case "esg": return .green
        case "brand": return .blue
        case "value": return .orange
        case "durability": return .purple
        case "social": return .pink
        case "health": return .red
        case "totalcost": return .cyan
        default: return .gray
        }
    }
}


#Preview {
    ScoreHistoryChartView(
        snapshots: (0..<10).map { i in
            ScoreSnapshotData(
                date: Calendar.current.date(byAdding: .day, value: -i, to: .now)!,
                score: Double.random(in: 0.3...0.9),
                strategyID: "esg"
            )
        },
        strategyID: "esg"
    )
    .padding()
}
