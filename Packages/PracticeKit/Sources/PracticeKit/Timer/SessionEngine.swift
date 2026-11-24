import Foundation

/// A finished segment, ready to be saved.
public struct FinishedSegment: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date
    public var activeDuration: TimeInterval
    public var target: SegmentTarget

    public init(id: UUID, startDate: Date, endDate: Date, activeDuration: TimeInterval, target: SegmentTarget) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activeDuration = activeDuration
        self.target = target
    }
}

/// A finished session, ready to be reviewed in the finish sheet and saved.
/// Also the payload the watch sends to the phone.
public struct FinishedSession: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date
    public var activeDuration: TimeInterval
    public var source: SessionSource
    public var instrumentID: UUID?
    public var segments: [FinishedSegment]
    public var pauses: [DateInterval]
    public var notes: String
    public var rating: Int?
    public var focus: Int?
    public var tags: [String]

    public init(
        id: UUID, startDate: Date, endDate: Date, activeDuration: TimeInterval,
        source: SessionSource, instrumentID: UUID?, segments: [FinishedSegment],
        pauses: [DateInterval], notes: String = "", rating: Int? = nil,
        focus: Int? = nil, tags: [String] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activeDuration = activeDuration
        self.source = source
        self.instrumentID = instrumentID
        self.segments = segments
        self.pauses = pauses
        self.notes = notes
        self.rating = rating
        self.focus = focus
        self.tags = tags
    }
}

/// Pure, timestamp-based session logic. All time comes from the injected
/// `now` provider, so tests control the clock.
public struct SessionEngine: Sendable {
    /// A segment shorter than this is retargeted instead of closed when
    /// switching, so fast taps don't create empty segments.
    public static let minimumSegmentDuration: TimeInterval = 1
    /// Sessions running longer than this get a "Still practicing?" nudge.
    public static let longSessionThreshold: TimeInterval = 4 * 60 * 60

    private let clock: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = now
    }

    /// Current time, never earlier than the session's last event (guards
    /// against the device clock jumping backward).
    private func now(for session: ActiveSession?) -> Date {
        let current = clock()
        guard let session else { return current }
        return max(current, session.latestEventDate)
    }

    public func start(
        instrument: InstrumentRef?,
        target: SegmentTarget = .general,
        source: SessionSource
    ) -> ActiveSession {
        let date = clock()
        return ActiveSession(
            startDate: date,
            source: source,
            instrument: instrument,
            segments: [ActiveSegment(startDate: date, target: target)],
            lastModified: date
        )
    }

    /// Closes the current segment and opens a new one at the same instant.
    /// Returns false when nothing changed.
    @discardableResult
    public func switchTo(_ target: SegmentTarget, in session: inout ActiveSession) -> Bool {
        let date = now(for: session)
        guard let last = session.segments.indices.last else {
            session.segments = [ActiveSegment(startDate: date, target: target)]
            session.lastModified = date
            return true
        }
        let current = session.segments[last]
        if current.target.isSameTarget(as: target) { return false }

        if session.activeDuration(of: current, at: date) < Self.minimumSegmentDuration {
            // Too short to keep: retarget it, then merge with the previous
            // segment if that one already has this target.
            session.segments[last].target = target
            if last > 0, session.segments[last - 1].target.isSameTarget(as: target) {
                session.segments.removeLast()
                session.segments[last - 1].endDate = nil
            }
        } else {
            session.segments[last].endDate = date
            session.segments.append(ActiveSegment(startDate: date, target: target))
        }
        session.lastModified = date
        return true
    }

    @discardableResult
    public func pause(_ session: inout ActiveSession) -> Bool {
        guard !session.isPaused else { return false }
        let date = now(for: session)
        session.pauses.append(ActivePause(startDate: date))
        session.lastModified = date
        return true
    }

    @discardableResult
    public func resume(_ session: inout ActiveSession) -> Bool {
        guard session.isPaused, let last = session.pauses.indices.last else { return false }
        let date = now(for: session)
        session.pauses[last].endDate = date
        session.lastModified = date
        return true
    }

    public func togglePause(_ session: inout ActiveSession) {
        if session.isPaused { resume(&session) } else { pause(&session) }
    }

    public func addNote(_ text: String, to session: inout ActiveSession) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.quickNotes.append(trimmed)
        session.lastModified = now(for: session)
    }

    /// Whether to send the "Still practicing?" notification.
    public func isLongRunning(_ session: ActiveSession) -> Bool {
        session.elapsed(at: now(for: session)) >= Self.longSessionThreshold
    }

    /// Closes every open segment and pause and computes durations.
    /// Segment durations always sum to the session's active duration.
    public func finish(_ session: ActiveSession) -> FinishedSession {
        let end = now(for: session)
        var closed = session
        if let last = closed.pauses.indices.last, closed.pauses[last].endDate == nil {
            closed.pauses[last].endDate = end
        }
        if let last = closed.segments.indices.last, closed.segments[last].endDate == nil {
            closed.segments[last].endDate = end
        }
        let segments = closed.segments.map { seg in
            FinishedSegment(
                id: seg.id,
                startDate: seg.startDate,
                endDate: seg.endDate ?? end,
                activeDuration: closed.activeDuration(of: seg, at: end),
                target: seg.target
            )
        }
        return FinishedSession(
            id: session.id,
            startDate: session.startDate,
            endDate: end,
            activeDuration: segments.reduce(0) { $0 + $1.activeDuration },
            source: session.source,
            instrumentID: session.instrument?.id,
            segments: segments,
            pauses: closed.pauses.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate ?? end)) },
            notes: session.quickNotes.joined(separator: "\n")
        )
    }
}
