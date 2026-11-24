import Foundation

/// Resolves the case where the phone and the watch each think they own the
/// active session (only one may be active at a time).
public enum SessionMerger {
    public enum Resolution: Sendable, Equatable {
        /// Same session on both sides; this is the newest copy.
        case keep(ActiveSession)
        /// Two different sessions. The earliest start wins; ask the user
        /// whether to merge the other into it or discard it.
        case conflict(winner: ActiveSession, loser: ActiveSession)
    }

    public static func resolve(local: ActiveSession, remote: ActiveSession) -> Resolution {
        if local.id == remote.id {
            return .keep(remote.lastModified > local.lastModified ? remote : local)
        }
        let localWins = (local.startDate, local.id.uuidString) < (remote.startDate, remote.id.uuidString)
        return localWins
            ? .conflict(winner: local, loser: remote)
            : .conflict(winner: remote, loser: local)
    }

    /// Folds the loser's segments into the winner's timeline. Each segment
    /// start becomes a "switch" event; events are replayed in time order so the
    /// result stays contiguous. The winner's pauses are kept.
    public static func merge(winner: ActiveSession, loser: ActiveSession) -> ActiveSession {
        struct Switch { let date: Date; let target: SegmentTarget; let id: UUID }

        var events = winner.segments.map { Switch(date: $0.startDate, target: $0.target, id: $0.id) }
        events += loser.segments
            .filter { $0.startDate > winner.startDate }
            .map { Switch(date: $0.startDate, target: $0.target, id: $0.id) }
        events.sort { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }

        var segments: [ActiveSegment] = []
        for event in events {
            if let last = segments.last, last.target.isSameTarget(as: event.target) { continue }
            if let lastIndex = segments.indices.last {
                segments[lastIndex].endDate = event.date
            }
            segments.append(ActiveSegment(id: event.id, startDate: event.date, target: event.target))
        }
        // Drop zero-length segments created by events at the same instant.
        segments = segments.filter { seg in seg.endDate.map { $0 > seg.startDate } ?? true }

        var merged = winner
        merged.segments = segments
        merged.quickNotes = winner.quickNotes + loser.quickNotes
        merged.lastModified = max(winner.lastModified, loser.lastModified)
        return merged
    }
}
