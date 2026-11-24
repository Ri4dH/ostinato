import Foundation

/// What a segment is about: a repertoire item, a free-text label, or general practice.
public struct SegmentTarget: Codable, Sendable, Hashable {
    public var itemID: UUID?
    /// Item title (denormalized for widgets/watch) or the free-text label.
    public var title: String?

    public init(itemID: UUID? = nil, title: String? = nil) {
        self.itemID = itemID
        self.title = title
    }

    public static let general = SegmentTarget()

    public static func item(_ id: UUID, title: String) -> SegmentTarget {
        SegmentTarget(itemID: id, title: title)
    }

    public static func label(_ text: String) -> SegmentTarget {
        SegmentTarget(itemID: nil, title: text)
    }

    /// Two targets mean the same thing (titles of items may be stale).
    public func isSameTarget(as other: SegmentTarget) -> Bool {
        if let itemID { return itemID == other.itemID }
        return other.itemID == nil && title == other.title
    }
}

public struct ActiveSegment: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date?
    public var target: SegmentTarget

    public init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil, target: SegmentTarget) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.target = target
    }
}

public struct ActivePause: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date?

    public init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// Minimal instrument info carried with an active session so widgets, the
/// Live Activity and the watch can show it without opening the store.
public struct InstrumentRef: Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var symbolName: String

    public init(id: UUID, name: String, colorHex: String, symbolName: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
    }

    public init(_ instrument: Instrument) {
        self.init(id: instrument.id, name: instrument.name,
                  colorHex: instrument.colorHex, symbolName: instrument.symbolName)
    }
}

/// The in-progress session. A value snapshot that is persisted after every
/// state change. Elapsed time is always derived from timestamps; nothing here
/// counts ticks.
public struct ActiveSession: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var source: SessionSource
    public var instrument: InstrumentRef?
    /// Contiguous, ordered. The last one is open (`endDate == nil`).
    public var segments: [ActiveSegment]
    /// Ordered. The last one may be open (session is paused).
    public var pauses: [ActivePause]
    /// Quick notes typed during the session.
    public var quickNotes: [String]
    public var lastModified: Date

    public init(
        id: UUID = UUID(),
        startDate: Date,
        source: SessionSource,
        instrument: InstrumentRef?,
        segments: [ActiveSegment],
        pauses: [ActivePause] = [],
        quickNotes: [String] = [],
        lastModified: Date
    ) {
        self.id = id
        self.startDate = startDate
        self.source = source
        self.instrument = instrument
        self.segments = segments
        self.pauses = pauses
        self.quickNotes = quickNotes
        self.lastModified = lastModified
    }

    public var isPaused: Bool { pauses.last.map { $0.endDate == nil } ?? false }

    public var currentSegment: ActiveSegment? { segments.last }

    public var currentTarget: SegmentTarget { currentSegment?.target ?? .general }

    /// Time spent paused inside `[from, to]`, counting an open pause up to `now`.
    public func pausedDuration(from: Date, to: Date, now: Date) -> TimeInterval {
        guard to > from else { return 0 }
        return pauses.reduce(0) { total, pause in
            let pauseEnd = pause.endDate ?? now
            let overlapStart = max(from, pause.startDate)
            let overlapEnd = min(to, pauseEnd)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
    }

    /// Total active time: now − start − paused time.
    public func elapsed(at now: Date) -> TimeInterval {
        let end = max(now, startDate)
        let wall = end.timeIntervalSince(startDate)
        return max(0, wall - pausedDuration(from: startDate, to: end, now: end))
    }

    /// Active time of a segment (its wall time minus overlapping pauses).
    public func activeDuration(of segment: ActiveSegment, at now: Date) -> TimeInterval {
        let end = max(segment.endDate ?? now, segment.startDate)
        let wall = end.timeIntervalSince(segment.startDate)
        return max(0, wall - pausedDuration(from: segment.startDate, to: end, now: now))
    }

    public func currentSegmentElapsed(at now: Date) -> TimeInterval {
        currentSegment.map { activeDuration(of: $0, at: now) } ?? 0
    }

    /// A reference date such that `now − reference == elapsed`. Stable while
    /// running, so `Text(timerInterval: reference...)` stays correct without
    /// per-second updates.
    public func timerReferenceDate(at now: Date) -> Date {
        now.addingTimeInterval(-elapsed(at: now))
    }

    public func currentSegmentReferenceDate(at now: Date) -> Date {
        now.addingTimeInterval(-currentSegmentElapsed(at: now))
    }

    /// Calendar day this session counts toward (the day it started).
    public func practiceDay(in calendar: Calendar) -> Date {
        calendar.startOfDay(for: startDate)
    }

    /// Item IDs used in this session, most recent first, without duplicates.
    public var recentItemIDs: [UUID] {
        var seen = Set<UUID>()
        return segments.reversed().compactMap(\.target.itemID).filter { seen.insert($0).inserted }
    }

    /// The latest timestamp recorded in this session. Used to keep time
    /// monotonic if the device clock jumps backward.
    var latestEventDate: Date {
        var latest = startDate
        for s in segments {
            latest = max(latest, s.startDate)
            if let e = s.endDate { latest = max(latest, e) }
        }
        for p in pauses {
            latest = max(latest, p.startDate)
            if let e = p.endDate { latest = max(latest, e) }
        }
        return latest
    }
}
