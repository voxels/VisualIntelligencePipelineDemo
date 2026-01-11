import WidgetKit
import SwiftUI

@main
struct VisualIntelligencePipelineWidgetBundle: WidgetBundle {
    var body: some Widget {
        VisualIntelligencePipelineHomeScreenWidget()
        VisualIntelligencePipelineLockScreenWidget()
        VisualIntelligencePipelineInteractiveWidget()
        DiverScanWidget()
    }
}
