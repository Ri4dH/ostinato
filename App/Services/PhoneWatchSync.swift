import Foundation
import PracticeKit
import SwiftData
import WatchConnectivity

/// Phone side of WatchConnectivity. The phone is the source of truth for the
/// store; the watch sends live session state and finished sessions.
@MainActor
final class PhoneWatchSync: NSObject {
    private unowned let model: AppModel
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var lastContext: PhoneContext?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Mirrors local session changes to the watch.
    func send(_ event: SessionEvent) {
        switch event {
        case .started(let s), .changed(let s), .restored(let s):
            deliverLive(.activeSession(s))
        case .finished(let f):
            deliverLive(.sessionEnded(f.id))
        case .discarded(let id):
            deliverLive(.sessionEnded(id))
        }
    }

    func pushContext(snapshot: WidgetSnapshot) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context = model.context
        let instruments = (try? context.fetch(FetchDescriptor<Instrument>(
            predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let items = RecentItems.fetch(in: context, instrumentID: nil, limit: 40)
        let phoneContext = PhoneContext(
            instruments: instruments.map(InstrumentRef.init),
            items: items.map { WatchItem(id: $0.id, title: $0.title, instrumentID: $0.instrument?.id) },
            goal: model.settings.goal,
            todaySeconds: snapshot.todaySeconds,
            todayDate: snapshot.todayDate,
            streak: snapshot.streak,
            lastInstrumentID: model.settings.lastInstrumentID,
            activeSession: model.sessionController.active,
            updatedAt: Date())
        guard phoneContext != lastContext else { return }
        lastContext = phoneContext
        if let payload = try? WatchMessage.context(phoneContext).encoded() {
            try? session.updateApplicationContext(payload)
        }
    }

    private func deliverLive(_ message: WatchMessage) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let payload = try? message.encoded() else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Fall back to the latest-state context on failure.
                Task { @MainActor in self.model.refreshDerivedState() }
            }
        } else {
            model.refreshDerivedState()   // context carries activeSession
        }
    }

    private func receive(_ message: WatchMessage) {
        let handler = PhoneSyncHandler(context: model.context, controller: model.sessionController)
        switch handler.handle(message) {
        case .none:
            break
        case .reply(let reply):
            if let payload = try? reply.encoded() { session?.transferUserInfo(payload) }
            model.storeDidChangeInBulk()
        case .conflict(let winner, let loser):
            model.conflict = SessionConflict(winner: winner, loser: loser)
        }
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.model.refreshDerivedState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchMessage.decode(message) else { return }
        Task { @MainActor in self.receive(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = WatchMessage.decode(userInfo) else { return }
        Task { @MainActor in self.receive(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let decoded = WatchMessage.decode(applicationContext) else { return }
        Task { @MainActor in self.receive(decoded) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.model.refreshDerivedState() }
    }
}
