import SwiftUI

struct MacAppCommands: Commands {
    var body: some Commands {
        SidebarCommands()
        
        CommandGroup(replacing: .newItem) {
            // No new items on Mac companion app
        }
        
        CommandGroup(after: .help) {
            Button("Documentation") {
                if let url = URL(string: "https://github.com/voxels/VisualIntelligencePipelineDemo") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
