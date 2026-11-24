import Foundation

/// One line of a manually logged session.
public struct ManualSegment: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var target: SegmentTarget
    public var minutes: Int

    public init(target: SegmentTarget, minutes: Int) {
        self.target = target
        self.minutes = minutes
    }
}

/// Builds a `FinishedSession` from a manual log (Log past session, Siri).
public enum ManualSessionBuilder {
    public static let maxMinutes = 24 * 60

    /// Segments are laid out back-to-back from `start`. Empty or zero-minute
    /// segments are dropped; if nothing is left, a single general segment of
    /// `fallbackMinutes` is used.
    public static func make(
        start: Date, segments: [ManualSegment], fallbackMinutes: Int = 0, instrumentID: UUID?,
        source: SessionSource = .manual, rating: Int? = nil, focus: Int? = nil,
        notes: String = "", tags: [String] = []
    ) -> FinishedSession? {
        var lines = segments.filter { $0.minutes > 0 }
        if lines.isEmpty, fallbackMinutes > 0 { lines = [ManualSegment(target: .general, minutes: fallbackMinutes)] }
        guard !lines.isEmpty else { return nil }

        var cursor = start
        var remaining = maxMinutes
        let finished: [FinishedSegment] = lines.compactMap { line in
            let minutes = min(line.minutes, remaining)
            guard minutes > 0 else { return nil }
            remaining -= minutes
            let seconds = TimeInterval(minutes * 60)
            defer { cursor = cursor.addingTimeInterval(seconds) }
            return FinishedSegment(id: UUID(), startDate: cursor, endDate: cursor.addingTimeInterval(seconds),
                                   activeDuration: seconds, target: line.target)
        }
        return FinishedSession(
            id: UUID(), startDate: start, endDate: cursor,
            activeDuration: finished.reduce(0) { $0 + $1.activeDuration },
            source: source, instrumentID: instrumentID, segments: finished, pauses: [],
            notes: notes, rating: rating, focus: focus, tags: tags)
    }
}
