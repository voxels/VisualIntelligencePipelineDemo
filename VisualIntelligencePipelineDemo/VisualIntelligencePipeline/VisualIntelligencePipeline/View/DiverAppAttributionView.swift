import SwiftUI
import SharedWithYou

struct AttributionViewWrapper: UIViewRepresentable {
    let highlight: SWHighlight

    func makeUIView(context: Context) -> SWAttributionView {
        let view = SWAttributionView()
        view.highlight = highlight
        view.displayContext = .summary
        view.horizontalAlignment = .leading
        view.backgroundStyle = .color
        return view
    }

    func updateUIView(_ uiView: SWAttributionView, context: Context) {
        uiView.highlight = highlight
    }
}
