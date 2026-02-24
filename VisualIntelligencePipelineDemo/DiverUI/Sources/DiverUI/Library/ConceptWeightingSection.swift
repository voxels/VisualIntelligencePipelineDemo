//
//  ConceptWeightingSection.swift
//  DiverUI — cross-platform
//
//  UIColor.secondarySystemBackground replaced with .secondary.opacity(0.1)
//

import SwiftUI
import SwiftData
import DiverKit

public struct ConceptWeightView: View {
    @Bindable public var concept: UserConcept
    public var onUpdate: () -> Void
    public var onDelete: () -> Void

    public init(concept: UserConcept, onUpdate: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.concept = concept
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(concept.name).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(String(format: "%.1f", concept.weight)).font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: $concept.weight, in: 0.1...5.0, step: 0.1, onEditingChanged: { _ in onUpdate() })
                .tint(.indigo)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Remove Concept", systemImage: "trash")
            }
        }
    }
}

public struct ConceptWeightingSection: View {
    public let item: ProcessedItem
    @Query private var userConcepts: [UserConcept]
    @Environment(\.modelContext) private var modelContext
    @State private var newConceptName: String = ""
    @State private var isAdding: Bool = false

    public init(item: ProcessedItem) { self.item = item }

    private var relevantConcepts: [UserConcept] {
        let tags = Set(item.tags + item.categories + item.visualTags)
        return userConcepts.filter { tags.contains($0.name) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Concept Weights").font(.headline)
            if relevantConcepts.isEmpty {
                Text("No linked concepts found.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(relevantConcepts) { concept in
                    ConceptWeightView(concept: concept, onUpdate: { save() }, onDelete: { removeConcept(concept) })
                }
            }
            if isAdding {
                HStack {
                    TextField("New Concept", text: $newConceptName).textFieldStyle(.roundedBorder)
                    Button("Add") { addConcept() }.disabled(newConceptName.isEmpty)
                }
            } else {
                Button(action: { isAdding.toggle() }) {
                    Label("Add Concept", systemImage: "plus.circle").font(.caption)
                }
            }
            Divider()
            Button(role: .destructive) { regenerateConcepts() } label: {
                Label("Clean & Regenerate Concepts", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.red)
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func save() { Task { @MainActor in try? modelContext.save() } }

    private func removeConcept(_ concept: UserConcept) {
        item.tags.removeAll { $0 == concept.name }
        item.categories.removeAll { $0 == concept.name }
        item.visualTags.removeAll { $0 == concept.name }
        save()
    }

    private func addConcept() {
        let name = newConceptName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let concept = UserConcept(name: name, definition: "User added concept", weight: 1.0)
        modelContext.insert(concept)
        item.tags.append(name)
        save()
        newConceptName = ""; isAdding = false
    }

    private func regenerateConcepts() {
        item.tags = []; item.categories = []; item.visualTags = []; item.purposes = []
        item.summary = nil
        Task {
            let pipeline = LocalPipelineService(modelContext: modelContext)
            await pipeline.regenerateSummary(for: item)
            await pipeline.extractConcepts(from: item)
            try? await pipeline.autoCreateConcepts(from: item)
            try? modelContext.save()
        }
    }
}
