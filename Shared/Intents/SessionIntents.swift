import AppIntents
import Foundation
import PracticeKit
import SwiftData

/// Starts a practice session. Runs in the app process (LiveActivityIntent)
/// so it can start the Live Activity.
struct StartPracticeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Practice"
    static let description = IntentDescription("Starts timing a practice session.")

    @Parameter(title: "Instrument") var instrument: InstrumentEntity?
    @Parameter(title: "Item") var item: PracticeItemEntity?

    init() {}

    init(instrument: InstrumentEntity? = nil, item: PracticeItemEntity? = nil) {
        self.instrument = instrument
        self.item = item
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Start practicing \(\.$item) on \(\.$instrument)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = IntentRuntime.controller
        if let active = controller.active {
            let title = active.currentTarget.title ?? String(localized: "practice")
            return .result(dialog: "Already practicing \(title).")
        }
        if let performer = IntentRuntime.performer {
            _ = performer.startSession(instrumentID: instrument?.id, itemID: item?.id, source: .siri)
        } else {
            let target = item.map { SegmentTarget.item($0.id, title: $0.title) } ?? .general
            controller.start(instrument: nil, target: target, source: .siri)
            IntentRuntime.didChange()
        }
        return .result(dialog: "Practice started.")
    }
}

struct PausePracticeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Practice"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard IntentRuntime.controller.isActive else { throw IntentError.noActiveSession }
        IntentRuntime.controller.pause()
        IntentRuntime.didChange()
        return .result()
    }
}

struct ResumePracticeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Practice"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard IntentRuntime.controller.isActive else { throw IntentError.noActiveSession }
        IntentRuntime.controller.resume()
        IntentRuntime.didChange()
        return .result()
    }
}

/// Pause/Resume button in the Live Activity.
struct TogglePausePracticeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Practice"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRuntime.controller.togglePause()
        IntentRuntime.didChange()
        return .result()
    }
}

/// "Next item" button: cycles through recently practiced items.
struct NextItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Practice Item"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = IntentRuntime.controller
        guard let active = controller.active else { throw IntentError.noActiveSession }
        if let next = IntentRuntime.performer?.nextItemTarget(after: active.currentTarget) {
            controller.switchTo(next)
            IntentRuntime.didChange()
        }
        return .result()
    }
}

struct SwitchItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Switch Practice Item"
    static let description = IntentDescription("Switches the running session to another piece or exercise.")

    @Parameter(title: "Item") var item: PracticeItemEntity

    init() {}
    init(item: PracticeItemEntity) { self.item = item }

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$item)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = IntentRuntime.controller
        guard controller.isActive else { throw IntentError.noActiveSession }
        controller.switchTo(.item(item.id, title: item.title))
        IntentRuntime.didChange()
        return .result(dialog: "Now practicing \(item.title).")
    }
}

/// Opens the app to the finish sheet (rating, notes, segment review).
struct FinishPracticeIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Practice"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard IntentRuntime.controller.isActive else { throw IntentError.noActiveSession }
        IntentRuntime.performer?.requestFinishSheet()
        return .result()
    }
}

/// Control Center toggle: on starts a session, off saves it as is.
struct TogglePracticeIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Practice"
    static let isDiscoverable = false

    @Parameter(title: "Practicing") var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = IntentRuntime.controller
        if value, !controller.isActive {
            if let performer = IntentRuntime.performer {
                _ = performer.startSession(instrumentID: nil, itemID: nil, source: .phone)
            } else {
                controller.start(instrument: nil)
                IntentRuntime.didChange()
            }
        } else if !value, controller.isActive {
            if let performer = IntentRuntime.performer {
                performer.saveWithoutReview()
            } else if let finished = controller.finish() {
                try SessionWriter.insert(finished, into: IntentRuntime.container().mainContext)
                controller.markSaved(finished)
                IntentRuntime.didChange()
            }
        }
        return .result()
    }
}
