import SwiftUI
import WidgetKit

@main
struct OstinatoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LockScreenWidget()
        PracticeLiveActivity()
        PracticeControl()
    }
}
