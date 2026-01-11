//
//  SharedWithYouView.swift
//  Diver
//
//  View component for displaying Shared with You content in the sidebar
//

import SwiftUI
import SharedWithYou
import DiverShared

#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)

struct SharedWithYouView: View {
    @ObservedObject var manager: SharedWithYouManager
    @State private var isExpanded: Bool = true

    var body: some View {
        if manager.isEnabled && !manager.highlights.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(manager.highlights, id: \.url) { highlight in
                    SharedHighlightRow(highlight: highlight, manager: manager)
                }
            } label: {
                Label("Shared with You", systemImage: "person.2.fill")
                    .badge(manager.highlights.count)
            }
        } else if manager.isEnabled {
            // Show empty state when enabled but no highlights
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared with You")
                    Text("No shared links")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "person.2")
                    .foregroundStyle(.secondary)
            }
            .disabled(true)
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct SharedHighlightRow: View {
    let highlight: SWHighlight
    let manager: SharedWithYouManager

    @State private var isProcessing = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 8) {
            defaultRow

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .opacity(isProcessing ? 0.6 : 1.0)
        .alert("Error Processing Link", isPresented: .constant(error != nil)) {
            Button("OK") {
                error = nil
            }
        } message: {
            if let error {
                Text(error)
            }
        }
    }

    private var defaultRow: some View {
        Button {
            processHighlight()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlight.url.absoluteString)
                        .font(.subheadline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        AttributionViewWrapper(highlight: highlight)
                            .frame(width: 150, height: 20) // Tight attribution
                        
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        Text("Messages")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func processHighlight() {
        guard !isProcessing else { return }

        isProcessing = true
        error = nil

        Task {
            do {
                try await manager.processHighlight(highlight)
                // Success - the highlight will be processed in the background
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// Fallback view for older OS versions
struct SharedWithYouPlaceholder: View {
    var body: some View {
        Label("Shared with You", systemImage: "shared.with.you")
            .foregroundStyle(.secondary)
    }
}

#Preview {
    if #available(iOS 16.0, macOS 13.0, *) {
        let queueDir = FileManager.default.temporaryDirectory.appendingPathComponent("queue-preview")
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        let store = try! DiverQueueStore(directoryURL: queueDir)
        let manager = SharedWithYouManager(queueStore: store, isEnabled: true)

        return List {
            SharedWithYouView(manager: manager)
        }
    } else {
        return Text("iOS 16.0+ required")
    }
}
