import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct HexDictationControl: ControlWidget {
    static let kind = "dev.rudek.typr.control.dictate"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleHexControlIntent()) {
                Label("Dictate", systemImage: "mic.fill")
                Text("Typr")
            }
        }
        .displayName("Dictate with Typr")
        .description("Starts or finishes on-device dictation and copies the text.")
    }
}
