import SwiftUI
import WidgetKit

@main
struct PolyplotWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PolyplotHomeWidget()
        PolyplotLockScreenWidget()
        PolyplotTimerLiveActivity()
    }
}
