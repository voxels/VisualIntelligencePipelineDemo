import SwiftUI
import SwiftData
import SharedWithYou
import DiverKit

/// Specialized profile view for displaying recognized faces and their associated context
/// from the local PersonVector identity database.
public struct PersonProfileView: View {
    let item: ProcessedItem
    @Environment(\.modelContext) private var modelContext
    
    @Query private var vectors: [PersonVector]
    
    public init(item: ProcessedItem) {
        self.item = item
        // Only fetch vectors that match the item's contact identifiers
        let ids = item.contactIdentifiers
        _vectors = Query(filter: #Predicate<PersonVector> { vector in
            ids.contains(vector.localIdentifier)
        })
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            if !vectors.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("People in Capture")
                        .font(.title3)
                        .bold()
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(vectors) { vector in
                                PersonFaceCard(vector: vector)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            // FastVLM Activity context if available
            if let activity = item.fastVLMAnalysis?.statements, !activity.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity Context")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(activity, id: \.self) { statement in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "smallcircle.filled.circle")
                                .font(.system(size: 8))
                                .padding(.top, 4)
                                .foregroundColor(.blue)
                            Text(statement)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Person Face Card
struct PersonFaceCard: View {
    let vector: PersonVector
    
    var body: some View {
        VStack(spacing: 8) {
            if let data = vector.faceCropData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.largeTitle)
                    )
            }
            
            Text(vector.name ?? "Unknown")
                .font(.caption.bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 80)
        }
        .padding(12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
