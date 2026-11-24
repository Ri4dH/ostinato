import Foundation
import Observation

/// Something that happened to the active session. Observers use it to update
/// the Live Activity, notify the watch, play haptics, etc.
public enum SessionEvent: Sendable, Equatable {
    case started(ActiveSession)
    case changed(ActiveSession)
    case finished(FinishedSession)
    case discarded(UUID)
    case restored(ActiveSession)
}

/// Owns the one active session on this device. Every state change is
/// persisted immediately, before observers are notified.
@MainActor
@Observable
public final class SessionController {
    public private(set) var active: ActiveSession?
    /// Set when a persist call failed; the UI can surface it.
    public private(set) var lastPersistenceError: String?

    @ObservationIgnored public let engine: SessionEngine
    @ObservationIgnored private let store: ActiveSessionPersisting
    @ObservationIgnored private var observers: [UUID: @MainActor (SessionEvent) -> Void] = [:]

    public init(engine: SessionEngine = SessionEngine(), store: ActiveSessionPersisting) {
        self.engine = engine
        self.store = store
        self.active = store.load()
    }

    public var isActive: Bool { active != nil }

    // MARK: Observers

    @discardableResult
    public func addObserver(_ handler: @escaping @MainActor (SessionEvent) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) { observers[id] = nil }

    private func emit(_ event: SessionEvent) {
        for handler in observers.values { handler(event) }
    }

    // MARK: Lifecycle

    /// Re-reads the persisted session. Call when returning to the foreground:
    /// a widget, intent or the watch may have changed it.
    public func reloadFromDisk() {
        let onDisk = store.load()
        guard onDisk != active else { return }
        active = onDisk
        if let onDisk { emit(.restored(onDisk)) }
    }

    /// Starts a session. Does nothing if one is already active (only one
    /// session at a time) and returns the existing one.
    @discardableResult
    public func start(
        instrument: InstrumentRef?,
        target: SegmentTarget = .general,
        source: SessionSource = .phone
    ) -> ActiveSession {
        if let active { return active }
        let session = engine.start(instrument: instrument, target: target, source: source)
        commit(session)
        emit(.started(session))
        return session
    }

    public func switchTo(_ target: SegmentTarget) {
        mutate { engine.switchTo(target, in: &$0) }
    }

    public func pause() { mutate { engine.pause(&$0) } }
    public func resume() { mutate { engine.resume(&$0) } }

    public func togglePause() {
        mutate { session in
            engine.togglePause(&session)
            return true
        }
    }

    public func addNote(_ text: String) {
        mutate { session in
            let before = session.quickNotes.count
            engine.addNote(text, to: &session)
            return session.quickNotes.count != before
        }
    }

    /// Ends the session and returns the result for the finish sheet. The
    /// snapshot stays on disk until `markSaved` or `discard`, so a crash while
    /// the finish sheet is open loses nothing.
    public func finish() -> FinishedSession? {
        guard let active else { return nil }
        return engine.finish(active)
    }

    /// Clears the active session after the finished session was saved.
    public func markSaved(_ finished: FinishedSession) {
        guard active?.id == finished.id else { return }
        clear()
        emit(.finished(finished))
    }

    public func discard() {
        guard let id = active?.id else { return }
        clear()
        emit(.discarded(id))
    }

    /// Applies a session received from the other device. Returns a conflict
    /// when both devices started different sessions; the caller asks the user.
    @discardableResult
    public func applyRemote(_ remote: ActiveSession) -> SessionMerger.Resolution? {
        guard let local = active else {
            commit(remote)
            emit(.restored(remote))
            return nil
        }
        let resolution = SessionMerger.resolve(local: local, remote: remote)
        if case .keep(let newest) = resolution {
            if newest != local {
                commit(newest)
                emit(.restored(newest))
            }
            return nil
        }
        return resolution
    }

    /// The user chose how to resolve a conflict.
    public func resolveConflict(winner: ActiveSession, loser: ActiveSession, merge: Bool) {
        let result = merge ? SessionMerger.merge(winner: winner, loser: loser) : winner
        commit(result)
        emit(.changed(result))
    }

    /// The other device finished or discarded the active session.
    public func applyRemoteEnd(sessionID: UUID) {
        guard active?.id == sessionID else { return }
        clear()
        emit(.discarded(sessionID))
    }

    // MARK: Private

    private func mutate(_ change: (inout ActiveSession) -> Bool) {
        guard var session = active else { return }
        guard change(&session) else { return }
        commit(session)
        emit(.changed(session))
    }

    private func commit(_ session: ActiveSession) {
        do {
            try store.save(session)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
        active = session
    }

    private func clear() {
        do { try store.clear() } catch { lastPersistenceError = error.localizedDescription }
        active = nil
    }
}
