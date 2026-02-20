//
//  EdgeDaemonDashboardView.swift
//  EdgeDaemon
//
//  Dashboard showing Neural Engine utilization, active models,
//  request throughput, and system health.
//

import SwiftUI
import Charts
import DiverKit

/// Full dashboard view for the edge daemon.
struct EdgeDaemonDashboardView: View {
    @Bindable var service: EdgeDaemonService
    @State private var throughputHistory: [ThroughputPoint] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Edge Node")
                            .font(.largeTitle.weight(.bold))
                        Text(Host.current().localizedName ?? "Mac")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    EdgeDaemonStatusBar(status: service.status)
                        .scaleEffect(1.5)
                }
                .padding()
                
                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    DashboardCard(
                        title: "Clients",
                        value: "\(service.connectedClients.count)",
                        icon: "iphone",
                        color: .blue
                    )
                    
                    DashboardCard(
                        title: "Requests",
                        value: "\(service.totalRequests)",
                        icon: "arrow.triangle.2.circlepath",
                        color: .green
                    )
                    
                    DashboardCard(
                        title: "Models",
                        value: "\(service.loadedModels.count)",
                        icon: "cpu",
                        color: .purple
                    )
                    
                    DashboardCard(
                        title: "Concurrent",
                        value: "\(service.maxConcurrentRequests)",
                        icon: "square.stack.3d.up",
                        color: .orange
                    )
                }
                .padding(.horizontal)
                
                // Throughput chart
                GroupBox("Request Throughput") {
                    if throughputHistory.isEmpty {
                        ContentUnavailableView(
                            "No Activity",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Request throughput will appear here.")
                        )
                        .frame(height: 150)
                    } else {
                        Chart(throughputHistory) { point in
                            BarMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Requests", point.count)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .frame(height: 150)
                    }
                }
                .padding(.horizontal)
                
                // Loaded models
                GroupBox("Available Models") {
                    ForEach(service.loadedModels, id: \.self) { model in
                        HStack {
                            Image(systemName: "cube.fill")
                                .foregroundStyle(.purple)
                            Text(model)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("Ready")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.1), in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal)
                
                // Connected clients
                GroupBox("Connected Devices") {
                    if service.connectedClients.isEmpty {
                        Text("No devices connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(service.connectedClients, id: \.self) { client in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundStyle(.blue)
                                Text(client)
                                    .font(.subheadline)
                                Spacer()
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }
}

/// Dashboard stat card.
private struct DashboardCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Throughput data point for charting.
struct ThroughputPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let count: Int
}
