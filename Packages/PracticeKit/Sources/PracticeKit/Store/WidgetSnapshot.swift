import Foundation

/// A tiny summary the app writes to the App Group after every change, so
/// widgets, complications and controls render instantly without opening the
/// SwiftData store.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable, Identifiable {
        public var date: Date
        public var minutes: Int
        public var id: Date { date }
        public init(date: Date, minutes: Int) { self.date = date; self.minutes = minutes }
    }

    public var todaySeconds: TimeInterval
    public var todayDate: Date
    public var goalMinutes: Int
    public var streak: Int
    /// Monday…Sunday of the current week (follows the user's calendar).
    public var week: [Day]
    public var lastInstrument: InstrumentRef?
    public var updatedAt: Date

    public init(todaySeconds: TimeInterval, todayDate: Date, goalMinutes: Int, streak: Int,
                week: [Day], lastInstrument: InstrumentRef?, updatedAt: Date) {
        self.todaySeconds = todaySeconds
        self.todayDate = todayDate
        self.goalMinutes = goalMinutes
        self.streak = streak
        self.week = week
        self.lastInstrument = lastInstrument
        self.updatedAt = updatedAt
    }

    public static let placeholder = WidgetSnapshot(
        todaySeconds: 24 * 60, todayDate: Date(), goalMinutes: 30, streak: 12,
        week: (0..<7).map { Day(date: Date().addingTimeInterval(Double($0 - 6) * 86_400), minutes: [20, 35, 0, 45, 30, 15, 24][$0]) },
        lastInstrument: nil, updatedAt: Date())

    /// Minutes practiced today, including the running session if any.
    /// Returns 0 when the snapshot is from an earlier day.
    public func todayMinutes(now: Date, calendar: Calendar, active: ActiveSession?) -> Int {
        var seconds = calendar.isDate(todayDate, inSameDayAs: now) ? todaySeconds : 0
        if let active, calendar.isDate(active.startDate, inSameDayAs: now) { seconds += active.elapsed(at: now) }
        return DurationText.minutes(seconds)
    }

    public func goalProgress(now: Date, calendar: Calendar, active: ActiveSession?) -> Double {
        guard goalMinutes > 0 else { return 0 }
        return min(1, Double(todayMinutes(now: now, calendar: calendar, active: active)) / Double(goalMinutes))
    }

    @MainActor
    public static func make(records: [SessionRecord], goal: GoalSettings, lastInstrument: InstrumentRef?,
                            now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let stats = StatsCalculator(calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 86_400 * 7)
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        return WidgetSnapshot(
            todaySeconds: stats.total(records, in: today),
            todayDate: now,
            goalMinutes: goal.dailyMinutes,
            streak: stats.streak(records, goal: goal, now: now).current,
            week: stats.bucketTotals(records, in: week).map { Day(date: $0.day, minutes: DurationText.minutes($0.seconds)) },
            lastInstrument: lastInstrument,
            updatedAt: now
        )
    }
}

public struct WidgetSnapshotStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: "widget-snapshot.json", directoryHint: .notDirectory)
    }

    public func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? FileActiveSessionStore.decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileActiveSessionStore.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
