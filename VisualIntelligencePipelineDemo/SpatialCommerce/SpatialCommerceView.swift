//
//  SpatialCommerceView.swift
//  SpatialCommerce
//
//  Main RealityView with spatial attachments for product score overlays.
//  Uses ARKit scene understanding to place score cards near detected objects.
//

import SwiftUI
import RealityKit

/// Main spatial commerce view with RealityKit scene and score attachments.
struct SpatialCommerceView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isImmersive = false
    @State private var detectedProducts: [DetectedProduct] = []
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue.gradient)
                
                Text("Spatial Commerce")
                    .font(.extraLargeTitle)
                
                Text("Point at products to see ethical score overlays")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Product count
            if !detectedProducts.isEmpty {
                HStack {
                    Image(systemName: "cube.transparent")
                        .foregroundStyle(.green)
                    Text("\(detectedProducts.count) products detected")
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.green.opacity(0.1), in: Capsule())
            }
            
            // Immersive toggle
            Button {
                Task {
                    if isImmersive {
                        await dismissImmersiveSpace()
                    } else {
                        await openImmersiveSpace(id: "ProductAnalysis")
                    }
                    isImmersive.toggle()
                }
            } label: {
                Label(
                    isImmersive ? "Stop Scanning" : "Start Scanning",
                    systemImage: isImmersive ? "stop.circle.fill" : "viewfinder"
                )
                .font(.title3)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(isImmersive ? .red : .blue)
            
            // Recent scans
            if !detectedProducts.isEmpty {
                VStack(alignment: .leading) {
                    Text("Recent Scans")
                        .font(.headline)
                    
                    ForEach(detectedProducts) { product in
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(product.scoreColor.opacity(0.2))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Text("\(Int(product.compositeScore * 100))")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(product.scoreColor)
                                }
                            
                            VStack(alignment: .leading) {
                                Text(product.name)
                                    .font(.subheadline.weight(.medium))
                                Text(product.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(40)
    }
}

/// A detected product in the spatial scene.
struct DetectedProduct: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let compositeScore: Float
    
    var scoreColor: Color {
        if compositeScore >= 0.7 { return .green }
        if compositeScore >= 0.4 { return .orange }
        return .red
    }
}
