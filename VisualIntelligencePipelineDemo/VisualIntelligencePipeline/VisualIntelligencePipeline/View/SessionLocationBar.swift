import SwiftUI
import DiverKit

struct SessionLocationBar: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    
    var body: some View {
        HStack {
            // Location Info (Tap to Edit)
            Button {
                viewModel.showingPlaceSelection = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(viewModel.isLocationPinned ? .yellow : .blue)
                    
                    if let place = viewModel.selectedPlace {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title ?? "Unknown Location")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            
                            if let addr = place.placeContext?.address {
                                Text(addr)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    } else if viewModel.pipelineStatus == .enriching {
                        Text("Locating...")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    } else {
                        Text("Add Location")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }
            }
            
            Spacer()
            
            // Pin Toggle
            if viewModel.selectedPlace != nil {
                Button {
                    withAnimation {
                        viewModel.isLocationPinned.toggle()
                    }
                    // Feedback
                    #if os(iOS)
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = viewModel.isLocationPinned ? .heavy : .light
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
                    #endif
                } label: {
                    Image(systemName: viewModel.isLocationPinned ? "pin.fill" : "pin")
                        .font(.body)
                        .foregroundStyle(viewModel.isLocationPinned ? .yellow : .white.opacity(0.5))
                        .padding(8)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.black.opacity(0.4))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}
