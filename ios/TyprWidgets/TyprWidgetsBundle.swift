import SwiftUI
import WidgetKit

@main
struct TyprWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TyprDictationLiveActivity()
        if #available(iOS 18.0, *) {
            TyprDictationControl()
        }
    }
}
