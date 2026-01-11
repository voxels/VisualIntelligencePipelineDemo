import WidgetKit
import SwiftUI

@main
struct DiverWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiverHomeScreenWidget()
        DiverLockScreenWidget()
        DiverInteractiveWidget()
    }
}
