import SwiftUI
import PlaygroundSupport
// Attempt to populate the playground with imports, if these fail you may need to build the "VisualIntelligencePipeline" scheme first.
import DiverKit
import DiverShared

// Basic setup to verify imports work
print("Diver Playground Started")

// Example usage
struct PlaygroundView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, Diver!")
            
            // Example of using a shared type if available (placeholder)
            // Text("DiverKit Version: \(DiverKitVersion.current)")
        }
        .padding()
    }
}

PlaygroundPage.current.setLiveView(PlaygroundView())
