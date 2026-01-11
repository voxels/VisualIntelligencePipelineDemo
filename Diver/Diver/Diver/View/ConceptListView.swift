import SwiftUI
import SwiftData
import DiverKit

struct ConceptListView: View {
    @Query(sort: \UserConcept.weight, order: .reverse) private var concepts: [UserConcept]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if concepts.isEmpty {
                ContentUnavailableView(
                    "No Concepts",
                    systemImage: "brain.head.profile",
                    description: Text("Concepts extracted from your items will appear here.")
                )
            } else {
                ForEach(concepts) { concept in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(concept.name)
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1f", concept.weight))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if !concept.definition.isEmpty {
                            Text(concept.definition)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteConcepts)
            }
        }
        .navigationTitle("Concepts")
        #if os(macOS)
        .navigationSubtitle("\(concepts.count) items")
        #endif
    }

    private func deleteConcepts(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(concepts[index])
            }
            try? modelContext.save()
        }
    }
}
