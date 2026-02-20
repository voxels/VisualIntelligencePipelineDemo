//
//  SpatialCommerceApp.swift
//  SpatialCommerce
//
//  visionOS app entry point for Spatial Commerce.
//  Uses RealityKit spatial attachments to overlay product scores
//  on real-world objects detected via ARKit.
//

import SwiftUI

@main
struct SpatialCommerceApp: App {
    @State private var immersiveSpaceIsShown = false
    
    var body: some Scene {
        WindowGroup {
            SpatialCommerceView()
        }
        .windowStyle(.plain)
        
        ImmersiveSpace(id: "ProductAnalysis") {
            ImmersiveScoreView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
