import SwiftUI
import SwiftData
import DiverKit

struct ConceptWeightView: View {
    @Bindable var concept: UserConcept
    var onUpdate: () -> Void

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
        // Predicate to find relevant concepts is tricky with simple Arrays in SwiftData predicates currently.
        // We will filter in memory for this MVP or use a broad query.
        // Fetching ALL UserConcepts might be heavy if there are thousands, but safe for hundreds.
    }

    var relevantConcepts: [UserConcept] {
        // Filter concepts that match item tags or categories
        let relevantTags = Set(item.tags + item.categories + item.themes)
        return userConcepts.filter { relevantTags.contains($0.name) }
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
                    ConceptWeightView(concept: concept) {
                        save()
                    }
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
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func save() {
        try? modelContext.save()
    }
    
    private func addConcept() {
        let name = newConceptName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let concept = UserConcept(name: name, definition: "User added concept", weight: 1.0)
        modelContext.insert(concept)
        item.tags.append(name) // Link by adding to tags
        try? modelContext.save()
        
        newConceptName = ""
        isAdding = false
    }
}
