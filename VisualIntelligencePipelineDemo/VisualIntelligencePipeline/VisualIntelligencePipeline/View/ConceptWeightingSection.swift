import SwiftUI
import SwiftData
import DiverKit

struct ConceptWeightView: View {
    @Bindable var concept: UserConcept
    var onUpdate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(concept.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.1f", concept.weight))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Slider(value: $concept.weight, in: 0.1...5.0, step: 0.1, onEditingChanged: { _ in
                onUpdate()
            })
            .tint(.indigo)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove Concept", systemImage: "trash")
            }
        }
    }
}

struct ConceptWeightingSection: View {
    let item: ProcessedItem
    @Query private var userConcepts: [UserConcept]
    @Environment(\.modelContext) private var modelContext
    @State private var newConceptName: String = ""
    @State private var isAdding: Bool = false

    init(item: ProcessedItem) {
        self.item = item
    }

    var relevantConcepts: [UserConcept] {
        // Filter concepts that match item tags or categories
        let relevantTags = Set(item.tags + item.categories + item.visualTags)
        return userConcepts.filter { relevantTags.contains($0.name) }
    }
    
    private func removeConcept(_ concept: UserConcept) {
        // Remove the concept name from the item's tags, categories, and visualTags
        // This unlinks the weight control for THIS item without deleting the global Concept definition
        item.tags.removeAll { $0 == concept.name }
        item.categories.removeAll { $0 == concept.name }
        item.visualTags.removeAll { $0 == concept.name }
        Task { @MainActor in try? modelContext.save() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Concept Weights")
                .font(.headline)
            
            if relevantConcepts.isEmpty {
                Text("No linked concepts found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relevantConcepts) { concept in
                    ConceptWeightView(concept: concept, onUpdate: {
                        save()
                    }, onDelete: {
                        removeConcept(concept)
                    })
                }
            }
            
            if isAdding {
                HStack {
                    TextField("New Concept", text: $newConceptName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addConcept()
                    }
                    .disabled(newConceptName.isEmpty)
                }
            } else {
                Button(action: { isAdding.toggle() }) {
                    Label("Add Concept", systemImage: "plus.circle")
                        .font(.caption)
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                regenerateConcepts()
            } label: {
                Label("Clean & Regenerate Concepts", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func save() {
        Task { @MainActor in try? modelContext.save() }
    }
    
    private func addConcept() {
        let name = newConceptName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let concept = UserConcept(name: name, definition: "User added concept", weight: 1.0)
        modelContext.insert(concept)
        item.tags.append(name) // Link by adding to tags
        Task { @MainActor in try? modelContext.save() }
        
        newConceptName = ""
        isAdding = false
    }
    
    private func regenerateConcepts() {
        // Clear existing derived concepts first
        item.tags = []
        item.categories = []
        item.visualTags = []
        item.purposes = []
        
        // Clear context data so enrichment runs fresh  
        // item.placeContextData = nil // Keep place context if it was manually selected
        // item.webContextData = nil // Keep web context
        
        // Clear the potentially styled summary so we regenerate from raw sources (OCR, Web)
        item.summary = nil
        
        Task {
            let pipeline = LocalPipelineService(modelContext: modelContext)
            
            // 1. Regenerate summary from raw evidence (skips old stale summary)
            await pipeline.regenerateSummary(for: item)
            
            // 2. Extract concepts from the NEW clean summary
            await pipeline.extractConcepts(from: item)
            
            // 3. Create user concepts
            try? await pipeline.autoCreateConcepts(from: item)
            
            try? modelContext.save()
            print("✅ Clean & Regenerate complete for item: \(item.id)")
        }
    }
}
