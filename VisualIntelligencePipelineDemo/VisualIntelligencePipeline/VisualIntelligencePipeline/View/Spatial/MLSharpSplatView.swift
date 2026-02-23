import SwiftUI
import RealityKit

#if os(iOS) || os(visionOS)
/// A RealityKit view that renders a 3D semantic representation (Gaussian Splat / Point Cloud)
/// returned by the Apple ml-sharp edge service.
public struct MLSharpSplatView: View {
    let splatData: Data
    
    // Gestures state for 3D manipulation
    @State private var rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var scale: Float = 1.0
    
    // The main container entity
    @State private var rootEntity = Entity()
    
    public init(splatData: Data) {
        self.splatData = splatData
    }
    
    public var body: some View {
        RealityView { content in
            // Add the root entity to the scene
            content.add(rootEntity)
            
            // Write the USDZ data to a temporary file because RealityKit requires a URL to load models
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
            do {
                try splatData.write(to: tempURL)
                
                // Load the USDZ mesh asynchronously
                Task {
                    do {
                        let loadRequest = try await Entity.load(contentsOf: tempURL)
                        
                        await MainActor.run {
                            // Center the loaded entity
                            loadRequest.position = [0, 0, 0]
                            rootEntity.addChild(loadRequest)
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                        }
                    } catch {
                        print("Failed to load USDZ: \(error)")
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }
            } catch {
                print("Failed to write temp USDZ file: \(error)")
            }
            
        } update: { content in
            // Apply gesture transforms
            rootEntity.transform.rotation = rotation
            rootEntity.transform.scale = [scale, scale, scale]
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Orbit rotation around Y and X axis based on drag
                    let deltaX = Float(value.translation.width) * 0.01
                    let deltaY = Float(value.translation.height) * 0.01
                    
                    let rotY = simd_quatf(angle: deltaX, axis: [0, 1, 0])
                    let rotX = simd_quatf(angle: deltaY, axis: [1, 0, 0])
                    
                    rotation = rotation * rotY * rotX
                }
        )
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    // Scale between 0.5x and 3.0x
                    let newScale = Float(value.magnification)
                    scale = min(max(newScale, 0.5), 3.0)
                }
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arkit")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7))
                .padding(12)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
                .padding(8)
        }
    }
}
#endif
