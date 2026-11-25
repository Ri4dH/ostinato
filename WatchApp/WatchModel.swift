import Foundation
import Observation
import PracticeKit
import UserNotifications
import WidgetKit

/// Watch state. Works fully offline; finished sessions wait in a persisted
/// outbox until the phone acknowledges them.
@MainActor
@Observable
final class WatchModel {
    static let shared = WatchModel()

    let controller: SessionController
    private(set) var context: PhoneContext
    private(set) var outbox: WatchOutbox
    var finishing: FinishedSession?
    /// Tap every N minutes to prompt switching (0 = off).
    var intervalHapticMinutes: Int {
        didSet {
            UserDefaults.standard.set(intervalHapticMinutes, forKey: "intervalHapticMinutes")
            scheduleIntervalHaptics()
        }
    }

    @ObservationIgnored let connector: WatchConnector
    @ObservationIgnored private let directory = AppIdentifiers.current.sharedDirectory

    private init() {
        if WatchDemo.isEnabled {
            controller = SessionController(store: InMemoryActiveSessionStore(WatchDemo.wantsSession ? WatchDemo.session() : nil))
            context = WatchDemo.context()
            outbox = WatchOutbox()
        } else {
            controller = SessionController(store: FileActiveSessionStore(directory: AppIdentifiers.current.sharedDirectory))
            context = Self.load(PhoneContext.self, "phone-context.json") ?? .empty
            outbox = Self.load(WatchOutbox.self, "outbox.json") ?? WatchOutbox()
        }
        intervalHapticMinutes = UserDefaults.standard.integer(forKey: "intervalHapticMinutes")
        connector = WatchConnector()
        connector.model = self
        controller.addObserver { [weak self] event in self?.handle(event) }
    }

    func activate() {
        guard !WatchDemo.isEnabled else { return }
        connector.activate()
        writeSnapshot()
    }

    // MARK: Derived

    var instruments: [InstrumentRef] { context.instruments }

    var lastInstrument: InstrumentRef? {
        context.instruments.first { $0.id == context.lastInstrumentID } ?? context.instruments.first
    }

    func items(for instrumentID: UUID?) -> [WatchItem] {
        context.items.filter { instrumentID == nil || $0.instrumentID == nil || $0.instrumentID == instrumentID }
    }

    func todayMinutes(at now: Date = Date()) -> Int {
        let calendar = Calendar.current
        var seconds = calendar.isDate(context.todayDate, inSameDayAs: now) ? context.todaySeconds : 0
        seconds += outbox.unsyncedSeconds(on: now, calendar: calendar)
        if let active = controller.active, calendar.isDate(active.startDate, inSameDayAs: now) {
            seconds += active.elapsed(at: now)
        }
        return DurationText.minutes(seconds)
    }

    // MARK: Actions

    func start(instrument: InstrumentRef?) {
        controller.start(instrument: instrument, source: .watch)
        requestNotificationPermissionIfNeeded()
    }

    func finish() {
        finishing = controller.finish()
    }

    func save(_ finished: FinishedSession) {
        outbox.enqueue(finished)
        persist(outbox, "outbox.json")
        controller.markSaved(finished)
        finishing = nil
        connector.sendFinished(finished)
        writeSnapshot()
    }

    func discard() {
        controller.discard()
        finishing = nil
    }

    // MARK: Sync

    func apply(_ message: WatchMessage) {
        switch message {
        case .context(let newContext):
            guard newContext.updatedAt >= context.updatedAt else { return }
            context = newContext
            persist(context, "phone-context.json")
            if let remote = newContext.activeSession { adopt(remote) }
            else if let active = controller.active, active.source != .watch, finishing == nil {
                // The phone no longer has the session it started.
                controller.applyRemoteEnd(sessionID: active.id)
            }
            writeSnapshot()
        case .activeSession(let remote):
            adopt(remote)
        case .sessionEnded(let id):
            controller.applyRemoteEnd(sessionID: id)
        case .ack(let ids):
            outbox.acknowledge(ids)
            persist(outbox, "outbox.json")
            writeSnapshot()
        case .finishedSession:
            break
        }
    }

    private func adopt(_ remote: ActiveSession) {
        if case let .conflict(winner, loser)? = controller.applyRemote(remote) {
            // The phone asks the user whether to merge; keep the earlier one meanwhile.
            controller.resolveConflict(winner: winner, loser: loser, merge: false)
        }
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .started(let s), .changed(let s):
            connector.sendLive(.activeSession(s))
        case .discarded(let id):
            connector.sendLive(.sessionEnded(id))
        case .finished(let f):
            connector.sendLive(.sessionEnded(f.id))
        case .restored:
            break
        }
        scheduleIntervalHaptics()
        writeSnapshot()
    }

    // MARK: Interval haptics (local notifications tap the wrist even when suspended)

    private func requestNotificationPermissionIfNeeded() {
        guard intervalHapticMinutes > 0 else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert]) }
    }

    private func scheduleIntervalHaptics() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard intervalHapticMinutes > 0, let session = controller.active, !session.isPaused else { return }
        let interval = TimeInterval(intervalHapticMinutes * 60)
        let elapsed = session.currentSegmentElapsed(at: Date())
        for k in 1...12 {
            let fireIn = interval * Double(k) - elapsed
            guard fireIn > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(intervalHapticMinutes * k) minutes on this item")
            content.body = session.currentTarget.title ?? String(localized: "Time to switch?")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "interval-\(k)", content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)))
        }
    }

    // MARK: Persistence

    private func writeSnapshot() {
        let snapshot = WidgetSnapshot(
            todaySeconds: TimeInterval(todayMinutes() * 60) - (controller.active?.elapsed(at: Date()) ?? 0),
            todayDate: Date(), goalMinutes: context.goal.dailyMinutes, streak: context.streak,
            week: [], lastInstrument: lastInstrument, updatedAt: Date())
        try? WidgetSnapshotStore(directory: directory).save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persist<T: Encodable>(_ value: T, _ name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: directory.appending(path: name), options: .atomic)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        let url = AppIdentifiers.current.sharedDirectory.appending(path: name)
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    var pendingOutbox: [FinishedSession] { outbox.pending }
}
