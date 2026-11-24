import Foundation
import PracticeKit
import WatchConnectivity

/// Watch side of WatchConnectivity.
@MainActor
final class WatchConnector: NSObject {
    weak var model: WatchModel?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Live state: message when the phone is reachable, else latest-state context.
    func sendLive(_ message: WatchMessage) {
        guard let session, session.activationState == .activated, let payload = try? message.encoded() else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                try? session.updateApplicationContext(payload)
            }
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    /// Finished sessions use guaranteed, queued delivery.
    func sendFinished(_ finished: FinishedSession) {
        guard let session, session.activationState == .activated,
              let payload = try? WatchMessage.finishedSession(finished).encoded() else { return }
        session.transferUserInfo(payload)
    }

    /// Re-queues anything the phone hasn't acknowledged and isn't already in flight.
    func resendPending() {
        guard let session, session.activationState == .activated, let model else { return }
        let inFlight = Set(session.outstandingUserInfoTransfers.compactMap { transfer -> UUID? in
            if case .finishedSession(let f)? = WatchMessage.decode(transfer.userInfo) { return f.id }
            return nil
        })
        for finished in model.pendingOutbox where !inFlight.contains(finished.id) {
            sendFinished(finished)
        }
    }

    private func deliver(_ message: WatchMessage) {
        model?.apply(message)
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = WatchMessage.decode(session.receivedApplicationContext)
        Task { @MainActor in
            if let context { self.deliver(context) }
            self.resendPending()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchMessage.decode(message) else { return }
        Task { @MainActor in self.deliver(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = WatchMessage.decode(userInfo) else { return }
        Task { @MainActor in self.deliver(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let decoded = WatchMessage.decode(applicationContext) else { return }
        Task { @MainActor in self.deliver(decoded) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.resendPending() }
    }
}
