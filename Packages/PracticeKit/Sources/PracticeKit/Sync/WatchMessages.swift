import Foundation

/// A repertoire item as the watch needs it.
public struct WatchItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var instrumentID: UUID?

    public init(id: UUID, title: String, instrumentID: UUID?) {
        self.id = id
        self.title = title
        self.instrumentID = instrumentID
    }
}

/// Phone → watch, latest-state-wins (`updateApplicationContext`).
public struct PhoneContext: Codable, Sendable, Equatable {
    public var instruments: [InstrumentRef]
    public var items: [WatchItem]
    public var goal: GoalSettings
    public var todaySeconds: TimeInterval
    public var todayDate: Date
    public var streak: Int
    public var lastInstrumentID: UUID?
    public var activeSession: ActiveSession?
    public var updatedAt: Date

    public init(instruments: [InstrumentRef], items: [WatchItem], goal: GoalSettings, todaySeconds: TimeInterval,
                todayDate: Date, streak: Int, lastInstrumentID: UUID?, activeSession: ActiveSession?, updatedAt: Date) {
        self.instruments = instruments
        self.items = items
        self.goal = goal
        self.todaySeconds = todaySeconds
        self.todayDate = todayDate
        self.streak = streak
        self.lastInstrumentID = lastInstrumentID
        self.activeSession = activeSession
        self.updatedAt = updatedAt
    }

    public static let empty = PhoneContext(instruments: [], items: [], goal: .default, todaySeconds: 0,
                                           todayDate: .distantPast, streak: 0, lastInstrumentID: nil,
                                           activeSession: nil, updatedAt: .distantPast)
}

/// Everything sent between phone and watch.
public enum WatchMessage: Codable, Sendable, Equatable {
    /// Live state of the active session (sendMessage when reachable).
    case activeSession(ActiveSession)
    /// The session ended on the sender (finished or discarded).
    case sessionEnded(UUID)
    /// A completed watch session (transferUserInfo, guaranteed delivery).
    case finishedSession(FinishedSession)
    /// Phone confirms these finished sessions are stored.
    case ack([UUID])
    /// Phone → watch state.
    case context(PhoneContext)

    static let key = "ostinato.message"

    public func encoded() throws -> [String: Any] {
        [Self.key: try Self.encoder.encode(self)]
    }

    public static func decode(_ dictionary: [String: Any]) -> WatchMessage? {
        guard let data = dictionary[key] as? Data else { return nil }
        return try? decoder.decode(WatchMessage.self, from: data)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}

/// Watch-side queue of finished sessions waiting for the phone's ack.
/// Persisted so nothing is lost if the watch app is terminated offline.
public struct WatchOutbox: Codable, Sendable, Equatable {
    public private(set) var pending: [FinishedSession] = []

    public init() {}

    public mutating func enqueue(_ session: FinishedSession) {
        guard !pending.contains(where: { $0.id == session.id }) else { return }
        pending.append(session)
    }

    public mutating func acknowledge(_ ids: [UUID]) {
        let acked = Set(ids)
        pending.removeAll { acked.contains($0.id) }
    }

    /// Seconds practiced today that the phone hasn't confirmed yet, so the
    /// watch can show an up-to-date total offline.
    public func unsyncedSeconds(on day: Date, calendar: Calendar) -> TimeInterval {
        pending.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.reduce(0) { $0 + $1.activeDuration }
    }
}
