@preconcurrency import ActivityKit
import Foundation
import PracticeKit

/// Starts, updates and ends the practice Live Activity. Updates only on state
/// changes; the clock renders itself with `Text(timerInterval:)`.
@MainActor
final class LiveActivityManager {
    private var activity: Activity<PracticeActivityAttributes>?

    func handle(_ event: SessionEvent) {
        switch event {
        case .started(let session), .restored(let session):
            start(session)
        case .changed(let session):
            update(session)
        case .finished, .discarded:
            end()
        }
    }

    /// On launch, reattach to a running activity or clean up stale ones.
    func adopt(_ session: ActiveSession?) {
        let running = Activity<PracticeActivityAttributes>.activities
        activity = running.first { $0.attributes.sessionID == session?.id }
        for stale in running where stale.attributes.sessionID != session?.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        if let session, activity == nil { start(session) }
    }

    func sync(_ session: ActiveSession?) {
        guard let session else { end(); return }
        if activity?.attributes.sessionID == session.id { update(session) } else { start(session) }
    }

    private func start(_ session: ActiveSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity, activity.attributes.sessionID == session.id {
            update(session)
            return
        }
        end()
        let attributes = PracticeActivityAttributes(
            sessionID: session.id,
            instrumentName: session.instrument?.name ?? String(localized: "Practice"),
            instrumentColorHex: session.instrument?.colorHex ?? InstrumentPalette.defaultHex,
            instrumentSymbol: session.instrument?.symbolName ?? "music.note")
        let content = ActivityContent(state: PracticeActivityAttributes.ContentState(session: session), staleDate: nil)
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    private func update(_ session: ActiveSession) {
        guard let activity else { start(session); return }
        let content = ActivityContent(state: PracticeActivityAttributes.ContentState(session: session), staleDate: nil)
        Task { await activity.update(content) }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
