//
//  MacContentView.swift
//  VisualIntelligenceMac
//
//  Root window for the native macOS companion app.
//  Three-column NavigationSplitView: Sessions | Items | Detail
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared

struct MacContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EdgeNodeInstallService.self) private var edgeNodeInstaller: EdgeNodeInstallService?

    @Query(sort: \SessionMetadata.createdAt, order: .reverse)
    private var sessions: [SessionMetadata]

    @State private var selectedSession: SessionMetadata?
    @State private var selectedItem: ProcessedItem?
    @State private var showEdgeNodeSettings = false

    var body: some View {
        NavigationSplitView {
            // ── Sidebar: Sessions ─────────────────────────────────────────
            List(sessions, id: \.id, selection: $selectedSession) { session in
                MacSessionRow(session: session)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .navigationTitle("Visual Intelligence")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    edgeNodeStatusButton
                }
            }

        } content: {
            // ── Middle: Items in selected session ─────────────────────────
            if let session = selectedSession {
                MacItemList(session: session, selectedItem: $selectedItem)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "rectangle.3.group",
                    description: Text("Choose a session from the sidebar to view its captures.")
                )
            }

        } detail: {
            // ── Detail: Full item view ────────────────────────────────────
            if let item = selectedItem {
                MacItemDetailView(item: item)
            } else {
                ContentUnavailableView(
                    "Select a Capture",
                    systemImage: "photo.stack",
                    description: Text("Choose a capture to view its analysis and metadata.")
                )
            }
        }
        .sheet(isPresented: $showEdgeNodeSettings) {
            if let edgeNodeInstaller {
                MacEdgeNodeStatusSheet(installer: edgeNodeInstaller)
            }
        }
    }

    // MARK: Edge Node toolbar button

    private var edgeNodeStatusButton: some View {
        Button {
            showEdgeNodeSettings = true
        } label: {
        HStack(spacing: 4) {
            Image(systemName: (edgeNodeInstaller?.isRunning ?? false)
                  ? "brain.filled.head.profile"
                  : "brain.head.profile")
            if edgeNodeInstaller?.isRunning ?? false {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
        }
    }
    .help((edgeNodeInstaller?.isRunning ?? false)
          ? "Edge Node running — click to manage"
          : "Edge Node not active — click to set up")
    }
}

// MARK: - Session Row

private struct MacSessionRow: View {
    let session: SessionMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title ?? "Session")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let place = session.locationName {
                    Label(place, systemImage: "mappin")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(session.createdAt, style: .relative)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Item List

private struct MacItemList: View {
    let session: SessionMetadata
    @Binding var selectedItem: ProcessedItem?

    var body: some View {
        List(session.items ?? [], id: \.id, selection: $selectedItem) { item in
            MacItemRow(item: item)
        }
        .navigationTitle(session.title ?? "Session")
    }
}

// MARK: - Item Row

private struct MacItemRow: View {
    let item: ProcessedItem

    var body: some View {
        HStack(spacing: 10) {
            if let thumb = item.rawPayload, let img = NSImage(data: thumb) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Untitled")
                    .font(.body)
                    .lineLimit(1)
                
                if let summary = item.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Item Detail

struct MacItemDetailView: View {
    let item: ProcessedItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Image
                if let data = item.rawPayload, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4)
                }

                // Title + summary
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title ?? "Untitled")
                        .font(.title2.bold())
                    if let summary = item.summary {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Meta chips
                let tags = item.tags
                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Location
                if let place = item.placeContext?.name {
                    Label(place, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle(item.title ?? "Capture")
    }
}

// MARK: - Edge Node Status Sheet (from toolbar button)

struct MacEdgeNodeStatusSheet: View {
    @Bindable var installer: EdgeNodeInstallService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: installer.isRunning
                      ? "brain.filled.head.profile"
                      : "brain.head.profile")
                    .font(.system(size: 28))
                    .foregroundStyle(installer.isRunning ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Visual Intelligence Node")
                        .font(.headline)
                    Text(installer.installStatus.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(installer.isRunning ? .green : .secondary)
                }

                Spacer()
            }

            switch installer.installStatus {
            case .notInstalled:
                Button("Enable Edge Node") { installer.install() }
                    .buttonStyle(.borderedProminent)
            case .requiresApproval:
                Button("Open System Settings") { installer.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
            case .running:
                Button("Disable Edge Node", role: .destructive) { installer.uninstall() }
                    .buttonStyle(.bordered)
            default:
                EmptyView()
            }

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - Simple flow layout helper

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
