import Foundation
import SwiftData

/// Phone-side handling of messages from the watch. Transport-agnostic so it
/// can be tested without WatchConnectivity.
@MainActor
public struct PhoneSyncHandler {
    public let context: ModelContext
    public let controller: SessionController

    public init(context: ModelContext, controller: SessionController) {
        self.context = context
        self.controller = controller
    }

    public enum Outcome: Equatable {
        case none
        case reply(WatchMessage)
        /// Both devices started different sessions; ask the user.
        case conflict(winner: ActiveSession, loser: ActiveSession)
    }

    public func handle(_ message: WatchMessage) -> Outcome {
        switch message {
        case .activeSession(let remote):
            if case let .conflict(winner, loser)? = controller.applyRemote(remote) {
                return .conflict(winner: winner, loser: loser)
            }
            return .none
        case .sessionEnded(let id):
            controller.applyRemoteEnd(sessionID: id)
            return .none
        case .finishedSession(let finished):
            do {
                try SessionWriter.insert(finished, into: context)   // idempotent by UUID
                controller.applyRemoteEnd(sessionID: finished.id)
                return .reply(.ack([finished.id]))
            } catch {
                return .none   // no ack → the watch resends later
            }
        case .ack, .context:
            return .none
        }
    }
}
