import Foundation

/// A lightweight, Sendable copy of a session for statistics. Built from the
/// SwiftData models once, then aggregated off the main thread.
public struct SessionRecord: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var activeDuration: TimeInterval
    public var instrumentID: UUID?
    public var rating: Int?
    public var focus: Int?
    public var tags: [String]
    public var segments: [SegmentRecord]

    public init(
        id: UUID = UUID(), startDate: Date, activeDuration: TimeInterval,
        instrumentID: UUID? = nil, rating: Int? = nil, focus: Int? = nil,
        tags: [String] = [], segments: [SegmentRecord] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.activeDuration = activeDuration
        self.instrumentID = instrumentID
        self.rating = rating
        self.focus = focus
        self.tags = tags
        self.segments = segments
    }
}

public struct SegmentRecord: Sendable, Hashable {
    public var itemID: UUID?
    public var category: ItemCategory?
    public var duration: TimeInterval

    public init(itemID: UUID?, category: ItemCategory?, duration: TimeInterval) {
        self.itemID = itemID
        self.category = category
        self.duration = duration
    }
}

extension SessionRecord {
    @MainActor
    public init(_ session: PracticeSession) {
        self.init(
            id: session.id,
            startDate: session.startDate,
            activeDuration: session.activeDuration,
            instrumentID: session.instrument?.id,
            rating: session.rating,
            focus: session.focus,
            tags: session.tags,
            segments: (session.segments ?? []).map {
                SegmentRecord(itemID: $0.item?.id, category: $0.item?.category, duration: $0.activeDuration)
            }
        )
    }
}

/// Time-range choices for the Stats tab.
public enum StatsRange: String, CaseIterable, Sendable, Identifiable {
    case week, month, year, all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .week: String(localized: "Week", bundle: .module)
        case .month: String(localized: "Month", bundle: .module)
        case .year: String(localized: "Year", bundle: .module)
        case .all: String(localized: "All", bundle: .module)
        }
    }

    /// The calendar interval containing `now`. `.all` starts at `earliest`.
    public func interval(containing now: Date, calendar: Calendar, earliest: Date?) -> DateInterval {
        let component: Calendar.Component
        switch self {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        case .all:
            let start = calendar.startOfDay(for: min(earliest ?? now, now))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: end)
        }
        return calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 0)
    }

    /// Bucket size for the per-day/per-period bar chart.
    public var bucket: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .year: .month
        case .all: .month
        }
    }
}
