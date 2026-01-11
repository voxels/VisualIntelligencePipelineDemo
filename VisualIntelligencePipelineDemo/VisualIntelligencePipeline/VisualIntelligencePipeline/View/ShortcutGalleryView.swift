//
//  ShortcutGalleryView.swift
//  Diver
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import DiverKit


// MARK: - Shortcut Models

struct ShortcutsManifest: Codable {
    let version: String
    let shortcuts: [ShortcutTemplate]
    let widgets: [WidgetTemplate]
    let advancedWorkflows: [AdvancedWorkflow]
    
    enum CodingKeys: String, CodingKey {
        case version, shortcuts, widgets
        case advancedWorkflows = "advanced_workflows"
    }
}

struct WidgetTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let type: String // e.g., "Standard", "Lock Screen", "Interactive"
    let sizes: [String] // e.g., ["small", "medium", "large"]
    let icon: String
}

struct ShortcutTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String // Changed to String for JSON
    let difficulty: String
    let estimatedTime: String
    let actions: [ShortcutAction]
    let useCases: [String]
    let customizations: [String]
    
    var steps: [ShortcutStep] {
        actions.enumerated().map { index, action in
            ShortcutStep(
                number: index + 1,
                title: action.intent ?? action.action ?? "Step",
                detail: action.parameters?.description ?? "Configuration",
                iconName: action.type == "intent" ? "wand.and.stars" : "gear"
            )
        }
    }
}

struct ShortcutAction: Codable {
    let type: String
    let intent: String?
    let action: String?
    let parameters: [String: AnyCodable]?
}

struct AdvancedWorkflow: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let difficulty: String
    let actions: [String]
}

struct ShortcutStep: Identifiable {
    var id: Int { number }
    let number: Int
    let title: String
    let detail: String
    let iconName: String
}

// Helper for heterogeneous dictionary decoding
struct AnyCodable: Codable, CustomStringConvertible {
    let value: Any

    var description: String {
        "\(value)"
    }

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) { value = x }
        else if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(Double.self) { value = x }
        else if let x = try? container.decode(Bool.self) { value = x }
        else if let x = try? container.decode([String: AnyCodable].self) { value = x.mapValues { $0.value } }
        else if let x = try? container.decode([AnyCodable].self) { value = x.map { $0.value } }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? String { try container.encode(x) }
        else if let x = value as? Int { try container.encode(x) }
        else if let x = value as? Double { try container.encode(x) }
        else if let x = value as? Bool { try container.encode(x) }
        else if let x = value as? [String: Any] { try container.encode(x.mapValues { AnyCodable($0) }) }
        else if let x = value as? [Any] { try container.encode(x.map { AnyCodable($0) }) }
        else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable value cannot be encoded")) }
    }
}

// MARK: - Extensions

extension Color {
    init(name: String) {
        switch name.lowercased() {
        case "blue": self = .blue
        case "purple": self = .purple
        case "orange": self = .orange
        case "green": self = .green
        case "yellow": self = .yellow
        case "red": self = .red
        default: self = .gray
        }
    }
}

// MARK: - Main Gallery View

struct ShortcutGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShortcut: ShortcutTemplate?
    @State private var manifest: ShortcutsManifest?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    if isLoading {
                        ProgressView()
                            .padding()
                    } else if let manifest = manifest {
                        ForEach(manifest.shortcuts) { shortcut in
                            ShortcutCard(shortcut: shortcut)
                                .onTapGesture {
                                    selectedShortcut = shortcut
                                }
                        }

                        widgetsSection(manifest.widgets)

                        advancedWorkflowsSection(manifest.advancedWorkflows)

                        tipsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Shortcut Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                loadManifest()
            }
            .sheet(item: $selectedShortcut) { shortcut in
                ShortcutDetailView(shortcut: shortcut)
            }
        }
    }

    private func loadManifest() {
        // Try DiverKit bundle first (now managing via SPM for reliable bundling)
        let diverKitBundle = DiverBundle.module
        print("🔍 Searching for shortcuts-manifest in DiverKit bundle: \(diverKitBundle.bundlePath)")
        var url = diverKitBundle.url(forResource: "shortcuts-manifest", withExtension: "json")
        
        if url != nil {
            print("✅ Found manifest in DiverKit bundle")
        }
        
        // Fallback to Shortcuts subdirectory (legacy)
        if url == nil {
            print("⚠️ Not found in DiverKit bundle, trying main bundle Shortcuts subfolder")
            url = Bundle.main.url(forResource: "shortcuts-manifest", withExtension: "json", subdirectory: "Shortcuts")
        }
        
        // Fallback to root (legacy)
        if url == nil {
            print("⚠️ Not found in subfolder, trying main bundle root")
            url = Bundle.main.url(forResource: "shortcuts-manifest", withExtension: "json")
        }
        
        guard let finalURL = url else {
            print("❌ Failed to find shortcuts-manifest.json in any bundle")
            isLoading = false
            return
        }

        print("📖 Loading manifest from: \(finalURL.absoluteString)")

        do {
            let data = try Data(contentsOf: finalURL)
            let decoder = JSONDecoder()
            self.manifest = try decoder.decode(ShortcutsManifest.self, from: data)
            print("✨ Successfully decoded manifest with \(self.manifest?.shortcuts.count ?? 0) shortcuts")
        } catch {
            print("❌ Failed to decode manifest: \(error)")
        }
        isLoading = false
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automate Diver")
                .font(.title2)
                .fontWeight(.bold)

            Text("Create powerful shortcuts to save, search, and share your links faster.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func widgetsSection(_ widgets: [WidgetTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interactive Widgets")
                .font(.headline)
                .padding(.top, 8)

            Text("Quickly access your library or save links directly from your Home or Lock Screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(widgets) { widget in
                        WidgetCard(widget: widget)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func advancedWorkflowsSection(_ workflows: [AdvancedWorkflow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Workflows")
                .font(.headline)
                .padding(.top, 8)

            Text("Combine these shortcuts with other Shortcuts actions for even more power:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(workflows) { workflow in
                    AdvancedWorkflowRow(
                        title: workflow.name,
                        description: workflow.description
                    )
                }
            }
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips")
                .font(.headline)
                .padding(.top, 8)

            TipRow(
                icon: "mic.fill",
                text: "Use \"Hey Siri\" + shortcut name to run with your voice"
            )

            TipRow(
                icon: "plus.circle.fill",
                text: "Add shortcuts to Action Button for one-tap access"
            )

            TipRow(
                icon: "square.and.arrow.up.fill",
                text: "Share shortcuts from Safari directly to Messages/Mail"
            )
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Shortcut Card

struct ShortcutCard: View {
    let shortcut: ShortcutTemplate

    var body: some View {
        let color = Color(name: shortcut.color)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: shortcut.icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcut.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        DifficultyBadge(difficulty: shortcut.difficulty)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(shortcut.estimatedTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(shortcut.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Shortcut Detail View

struct ShortcutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let shortcut: ShortcutTemplate

    var body: some View {
        let color = Color(name: shortcut.color)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: shortcut.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(color)
                            .frame(width: 100, height: 100)
                            .background(color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        VStack(spacing: 8) {
                            Text(shortcut.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(shortcut.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                DifficultyBadge(difficulty: shortcut.difficulty)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Label(shortcut.estimatedTime, systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    Divider()

                    // Steps
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to Create")
                            .font(.headline)

                        ForEach(shortcut.steps) { step in
                            StepRow(step: step)
                        }

                        // Add to Shortcuts button
                        Button(action: openShortcutsApp) {
                            Label("Open Shortcuts App", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(color)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 8)
                    }

                    Divider()

                    // Use Cases
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Use Cases")
                            .font(.headline)

                        ForEach(shortcut.useCases, id: \.self) { useCase in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(useCase)
                                    .font(.subheadline)
                            }
                        }
                    }

                    Divider()

                    // Customizations
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Customization Ideas")
                            .font(.headline)

                        ForEach(shortcut.customizations, id: \.self) { customization in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(customization)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

#Preview {
    ShortcutGalleryView()
}

// MARK: - Supporting Views

struct DifficultyBadge: View {
    let difficulty: String

    var badgeColor: Color {
        switch difficulty.lowercased() {
        case "easy": return .green
        case "medium": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }

    var body: some View {
        Text(difficulty.capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.1))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }
}

struct StepRow: View {
    let step: ShortcutStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Text("\(step.number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }

            // Step content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: step.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(step.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AdvancedWorkflowRow: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.purple)
                .font(.caption)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .font(.caption)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct WidgetCard: View {
    let widget: WidgetTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 140, height: 100)
                
                Image(systemName: widget.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(widget.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Text(widget.type)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(widget.sizes.joined(separator: ", "))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 140)
    }
}
