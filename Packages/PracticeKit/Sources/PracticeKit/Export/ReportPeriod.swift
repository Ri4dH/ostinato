import Foundation

/// Periods offered for the shareable practice report.
public enum ReportPeriod: String, CaseIterable, Sendable, Identifiable {
    case thisWeek, lastWeek, last30Days, thisMonth, lastMonth

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .thisWeek: String(localized: "This week", bundle: .module)
        case .lastWeek: String(localized: "Last week", bundle: .module)
        case .last30Days: String(localized: "Last 30 days", bundle: .module)
        case .thisMonth: String(localized: "This month", bundle: .module)
        case .lastMonth: String(localized: "Last month", bundle: .module)
        }
    }

    /// Whole calendar days; the end is exclusive.
    public func interval(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        func whole(_ component: Calendar.Component, offset: Int) -> DateInterval {
            let anchor = calendar.date(byAdding: component, value: offset, to: now) ?? now
            return calendar.dateInterval(of: component, for: anchor) ?? DateInterval(start: today, end: tomorrow)
        }
        switch self {
        case .thisWeek: return whole(.weekOfYear, offset: 0)
        case .lastWeek: return whole(.weekOfYear, offset: -1)
        case .thisMonth: return whole(.month, offset: 0)
        case .lastMonth: return whole(.month, offset: -1)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        }
    }

    /// File-name friendly slug, e.g. "2026-11-01_to_2026-11-30".
    public func fileStem(now: Date, calendar: Calendar) -> String {
        let interval = interval(now: now, calendar: calendar)
        let style = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        let last = interval.end.addingTimeInterval(-1)
        return "\(interval.start.formatted(style))_to_\(last.formatted(style))"
    }
}
