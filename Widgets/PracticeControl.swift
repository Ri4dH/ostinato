import AppIntents
import PracticeKit
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action button: start or stop practice.
struct PracticeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ostinato.control.practice", provider: PracticeControlValue()) { isOn in
            ControlWidgetToggle("Practice", isOn: isOn, action: TogglePracticeIntent()) { on in
                Label(on ? "Practicing" : "Practice", systemImage: on ? "stop.fill" : "music.note")
            }
            .tint(.indigo)
        }
        .displayName("Practice")
        .description("Start or finish a practice session.")
    }
}

struct PracticeControlValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        FileActiveSessionStore(directory: AppIdentifiers.current.sharedDirectory).load() != nil
    }
}
