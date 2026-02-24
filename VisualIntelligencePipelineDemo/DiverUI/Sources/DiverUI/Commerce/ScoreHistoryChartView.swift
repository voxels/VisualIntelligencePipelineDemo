//
//  ScoreHistoryChartView.swift
//  DiverUI — cross-platform
//

import SwiftUI
import Charts
import DiverKit
import DiverShared

public struct ScoreHistoryChartView: View {
    public let snapshots: [ScoreSnapshotData]
    public let strategyID: String

    public init(snapshots: [ScoreSnapshotData], strategyID: String) {
        self.snapshots = snapshots
        self.strategyID = strategyID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score History").font(.headline)
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Scores will appear here after pipeline runs.")
                ).frame(height: 200)
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(x: .value("Date", snapshot.date), y: .value("Score", snapshot.score))
                        .foregroundStyle(colorForStrategy(strategyID))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Date", snapshot.date), y: .value("Score", snapshot.score))
                        .foregroundStyle(colorForStrategy(strategyID))
                        .symbolSize(30)
                    AreaMark(x: .value("Date", snapshot.date), y: .value("Score", snapshot.score))
                        .foregroundStyle(.linearGradient(
                            colors: [colorForStrategy(strategyID).opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v * 100))%").font(.caption2) }
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
        case "esg": .green; case "brand": .blue; case "value": .orange
        case "durability": .purple; case "social": .pink; case "health": .red
        case "totalcost": .cyan; default: .gray
        }
    }
}
