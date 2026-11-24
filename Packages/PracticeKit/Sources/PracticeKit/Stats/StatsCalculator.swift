import Foundation

public struct DayTotal: Sendable, Hashable, Identifiable {
    public var day: Date
    public var seconds: TimeInterval
    public var id: Date { day }
    public var minutes: Double { seconds / 60 }
}

public struct KeyedTotal<Key: Hashable & Sendable>: Sendable, Hashable {
    public var key: Key
    public var seconds: TimeInterval
    public var minutes: Double { seconds / 60 }
}

public struct InstrumentDayTotal: Sendable, Hashable, Identifiable {
    public var bucket: Date
    public var instrumentID: UUID?
    public var seconds: TimeInterval
    public var id: String { "\(bucket.timeIntervalSince1970)-\(instrumentID?.uuidString ?? "none")" }
}

public struct StreakInfo: Sendable, Hashable {
    public var current: Int
    public var longest: Int
    /// True when today hasn't been practiced yet but the streak is still alive.
    public var isPendingToday: Bool

    public init(current: Int, longest: Int, isPendingToday: Bool) {
        self.current = current
        self.longest = longest
        self.isPendingToday = isPendingToday
    }
}

public struct GoalCompletion: Sendable, Hashable {
    public var daysMet: Int
    public var daysElapsed: Int
    public var weeksMet: Int
    public var weeksElapsed: Int

    public init(daysMet: Int, daysElapsed: Int, weeksMet: Int, weeksElapsed: Int) {
        self.daysMet = daysMet
        self.daysElapsed = daysElapsed
        self.weeksMet = weeksMet
        self.weeksElapsed = weeksElapsed
    }

    /// Share of weeks that hit the days-per-week goal.
    public var weeklyRate: Double { weeksElapsed == 0 ? 0 : Double(weeksMet) / Double(weeksElapsed) }
    public var dailyRate: Double { daysElapsed == 0 ? 0 : Double(daysMet) / Double(daysElapsed) }
}

public struct WeeklyAverage: Sendable, Hashable, Identifiable {
    public var weekStart: Date
    public var rating: Double?
    public var focus: Double?
    public var id: Date { weekStart }
}

/// All statistics math. Pure: no SwiftData, injectable calendar.
public struct StatsCalculator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    // MARK: Totals

    /// Practice time per day (sessions count toward the day they started).
    public func dayTotals(_ records: [SessionRecord]) -> [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for r in records { totals[calendar.startOfDay(for: r.startDate), default: 0] += r.activeDuration }
        return totals
    }

    /// One entry per bucket (day or month) in the interval, zeros included.
    public func bucketTotals(
        _ records: [SessionRecord], in interval: DateInterval, bucket: Calendar.Component = .day
    ) -> [DayTotal] {
        var totals: [Date: TimeInterval] = [:]
        for r in records where interval.contains(r.startDate) {
            totals[bucketStart(r.startDate, bucket), default: 0] += r.activeDuration
        }
        return buckets(in: interval, bucket).map { DayTotal(day: $0, seconds: totals[$0] ?? 0) }
    }

    public func instrumentBucketTotals(
        _ records: [SessionRecord], in interval: DateInterval, bucket: Calendar.Component = .day
    ) -> [InstrumentDayTotal] {
        var totals: [Date: [UUID?: TimeInterval]] = [:]
        for r in records where interval.contains(r.startDate) {
            totals[bucketStart(r.startDate, bucket), default: [:]][r.instrumentID, default: 0] += r.activeDuration
        }
        return totals.keys.sorted().flatMap { day in
            totals[day, default: [:]]
                .sorted { ($0.key?.uuidString ?? "") < ($1.key?.uuidString ?? "") }
                .map { InstrumentDayTotal(bucket: day, instrumentID: $0.key, seconds: $0.value) }
        }
    }

    public func totalsByInstrument(_ records: [SessionRecord]) -> [KeyedTotal<UUID?>] {
        var totals: [UUID?: TimeInterval] = [:]
        for r in records { totals[r.instrumentID, default: 0] += r.activeDuration }
        return totals.map { KeyedTotal(key: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    /// Top items by time. Segments without an item are excluded.
    public func topItems(_ records: [SessionRecord], limit: Int = 10) -> [KeyedTotal<UUID>] {
        var totals: [UUID: TimeInterval] = [:]
        for r in records {
            for s in r.segments { if let id = s.itemID { totals[id, default: 0] += s.duration } }
        }
        return Array(totals.map { KeyedTotal(key: $0.key, seconds: $0.value) }
            .sorted { ($0.seconds, $0.key.uuidString) > ($1.seconds, $1.key.uuidString) }
            .prefix(limit))
    }

    /// Time per category. Unlinked segments count as `.other`.
    public func totalsByCategory(_ records: [SessionRecord]) -> [KeyedTotal<ItemCategory>] {
        var totals: [ItemCategory: TimeInterval] = [:]
        for r in records {
            for s in r.segments { totals[s.category ?? .other, default: 0] += s.duration }
        }
        return totals.map { KeyedTotal(key: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    public func total(_ records: [SessionRecord], in interval: DateInterval? = nil) -> TimeInterval {
        records.reduce(0) { sum, r in
            guard interval?.contains(r.startDate) ?? true else { return sum }
            return sum + r.activeDuration
        }
    }

    /// Time spent on one item, optionally within an interval.
    public func itemTotal(_ itemID: UUID, _ records: [SessionRecord], in interval: DateInterval? = nil) -> TimeInterval {
        records.reduce(0) { sum, r in
            guard interval?.contains(r.startDate) ?? true else { return sum }
            return sum + r.segments.reduce(0) { $0 + ($1.itemID == itemID ? $1.duration : 0) }
        }
    }

    /// Minutes per week on one item, zeros included, for the last `weeks` weeks.
    public func itemWeeklyTotals(_ itemID: UUID, _ records: [SessionRecord], weeks: Int, now: Date) -> [DayTotal] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek.start)
        else { return [] }
        let interval = DateInterval(start: start, end: thisWeek.end)
        var totals: [Date: TimeInterval] = [:]
        for r in records where interval.contains(r.startDate) {
            let seconds = r.segments.reduce(0) { $0 + ($1.itemID == itemID ? $1.duration : 0) }
            if seconds > 0 { totals[bucketStart(r.startDate, .weekOfYear), default: 0] += seconds }
        }
        return buckets(in: interval, .weekOfYear).map { DayTotal(day: $0, seconds: totals[$0] ?? 0) }
    }

    // MARK: Streaks and goals

    /// Streak of practiced days. With rest days on, up to `7 − daysPerWeek`
    /// missed days per calendar week don't break it. Today never breaks it.
    public func streak(_ records: [SessionRecord], goal: GoalSettings, now: Date) -> StreakInfo {
        let totals = dayTotals(records)
        let practiced = Set(totals.filter { $0.value > 0 }.keys)
        let today = calendar.startOfDay(for: now)
        guard let first = practiced.min(), first <= today else {
            return StreakInfo(current: 0, longest: 0, isPendingToday: false)
        }
        let allowance = goal.restDaysPerWeek
        var run = 0, longest = 0, misses = 0
        var week: Date?
        var day = first
        while day <= today {
            let thisWeek = bucketStart(day, .weekOfYear)
            if thisWeek != week { week = thisWeek; misses = 0 }
            if practiced.contains(day) {
                run += 1
                longest = max(longest, run)
            } else if day != today, run > 0 {
                misses += 1
                if misses > allowance { run = 0; misses = 0 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return StreakInfo(current: run, longest: longest, isPendingToday: run > 0 && !practiced.contains(today))
    }

    /// Days meeting the daily minutes goal, and weeks meeting days-per-week,
    /// counted from the interval start up to today.
    public func goalCompletion(
        _ records: [SessionRecord], goal: GoalSettings, in interval: DateInterval, now: Date
    ) -> GoalCompletion {
        let totals = dayTotals(records)
        let end = min(interval.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
        guard end > interval.start else { return GoalCompletion(daysMet: 0, daysElapsed: 0, weeksMet: 0, weeksElapsed: 0) }
        let range = DateInterval(start: interval.start, end: end)
        var daysMet = 0, daysElapsed = 0
        var weekHits: [Date: Int] = [:]
        for day in buckets(in: range, .day) {
            daysElapsed += 1
            let week = bucketStart(day, .weekOfYear)
            weekHits[week, default: 0] += 0
            if (totals[day] ?? 0) >= goal.dailySeconds {
                daysMet += 1
                weekHits[week, default: 0] += 1
            }
        }
        let weeksMet = weekHits.values.filter { $0 >= goal.daysPerWeek }.count
        return GoalCompletion(daysMet: daysMet, daysElapsed: daysElapsed, weeksMet: weeksMet, weeksElapsed: weekHits.count)
    }

    public func weeklyAverages(_ records: [SessionRecord], in interval: DateInterval) -> [WeeklyAverage] {
        var ratings: [Date: [Int]] = [:], focus: [Date: [Int]] = [:]
        for r in records where interval.contains(r.startDate) {
            let week = bucketStart(r.startDate, .weekOfYear)
            if let v = r.rating { ratings[week, default: []].append(v) }
            if let v = r.focus { focus[week, default: []].append(v) }
        }
        func avg(_ values: [Int]?) -> Double? {
            guard let values, !values.isEmpty else { return nil }
            return Double(values.reduce(0, +)) / Double(values.count)
        }
        return Set(ratings.keys).union(focus.keys).sorted()
            .map { WeeklyAverage(weekStart: $0, rating: avg(ratings[$0]), focus: avg(focus[$0])) }
    }

    // MARK: Helpers

    public func bucketStart(_ date: Date, _ component: Calendar.Component) -> Date {
        if component == .day { return calendar.startOfDay(for: date) }
        return calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public func buckets(in interval: DateInterval, _ component: Calendar.Component) -> [Date] {
        var result: [Date] = []
        var cursor = bucketStart(interval.start, component)
        while cursor < interval.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }
}
