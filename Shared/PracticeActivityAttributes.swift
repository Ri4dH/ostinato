import ActivityKit
import Foundation
import PracticeKit

/// Live Activity for the active practice session. The clock is rendered with
/// `Text(timerInterval:)`, so the activity only updates on state changes.
struct PracticeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var itemTitle: String
        var isPaused: Bool
        /// `now − timerReference == elapsed` while running.
        var timerReference: Date
        /// Elapsed seconds frozen at the moment of pausing.
        var pausedElapsed: TimeInterval

        init(session: ActiveSession, now: Date = Date()) {
            itemTitle = session.currentTarget.title ?? String(localized: "General practice")
            isPaused = session.isPaused
            timerReference = session.timerReferenceDate(at: now)
            pausedElapsed = session.elapsed(at: now)
        }
    }

    var sessionID: UUID
    var instrumentName: String
    var instrumentColorHex: String
    var instrumentSymbol: String
}
