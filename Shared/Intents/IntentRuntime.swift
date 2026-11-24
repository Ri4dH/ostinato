import AppIntents
import Foundation
import PracticeKit
import SwiftData
import WidgetKit

/// Implemented by the app. Intents that run in the app's process (Siri,
/// Shortcuts, Live Activity and widget buttons) go through it so the Live
/// Activity, watch and widgets stay in sync.
@MainActor
protocol PracticeIntentPerforming: AnyObject {
    var sessionController: SessionController { get }
    var modelContainer: ModelContainer { get }
    func startSession(instrumentID: UUID?, itemID: UUID?, source: SessionSource) -> ActiveSession
    func nextItemTarget(after current: SegmentTarget) -> SegmentTarget?
    func requestFinishSheet()
    func saveWithoutReview()
    func dataDidChange()
}

/// Bridges intents to the app, with a file-only fallback for the rare case an
/// intent runs in the widget extension's process.
@MainActor
enum IntentRuntime {
    static weak var performer: (any PracticeIntentPerforming)?

    private static var fallbackController: SessionController?
    private static var fallbackContainer: ModelContainer?

    static var controller: SessionController {
        if let performer { return performer.sessionController }
        if let fallbackController {
            fallbackController.reloadFromDisk()
            return fallbackController
        }
        let store = FileActiveSessionStore(directory: AppIdentifiers.current.sharedDirectory)
        let controller = SessionController(store: store)
        fallbackController = controller
        return controller
    }

    static func container() throws -> ModelContainer {
        if let performer { return performer.modelContainer }
        if let fallbackContainer { return fallbackContainer }
        // Local-only: only the app process mirrors to CloudKit.
        let container = try PracticeStore.makeContainer(syncEnabled: false)
        fallbackContainer = container
        return container
    }

    static func didChange() {
        if let performer {
            performer.dataDidChange()
        } else {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveSession
    case invalidMinutes

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveSession: "No practice session is running."
        case .invalidMinutes: "Enter between 1 and 1,440 minutes."
        }
    }
}
