//
//  ClientListView.swift
//  EdgeDaemon
//
//  Detailed view of connected iOS clients with request statistics.
//

import SwiftUI

/// Connected client detail view.
struct ClientListView: View {
    let clients: [String]
    let totalRequests: Int
    
    var body: some View {
        List {
            Section("Active Connections (\(clients.count))") {
                if clients.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No devices connected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("iOS devices on the same network will appear here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        Spacer()
                    }
                } else {
                    ForEach(clients, id: \.self) { client in
                        HStack {
                            Image(systemName: "iphone")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading) {
                                Text(client)
                                    .font(.subheadline.weight(.medium))
                                Text("Connected via TLS 1.3")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Circle()
                                .fill(.green)
                                .frame(width: 10, height: 10)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Summary") {
                LabeledContent("Total Requests Served") {
                    Text("\(totalRequests)")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }
}
