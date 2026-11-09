import SwiftUI
import WidgetKit

@main
struct HourlarkWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimerWidget()
        TimerLiveActivity()
    }
}
