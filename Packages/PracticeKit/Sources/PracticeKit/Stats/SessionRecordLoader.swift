import Foundation
import SwiftData

/// Loads `SessionRecord`s with four flat fetches instead of walking
/// relationships per session (which faults once per session and is slow with
/// thousands of sessions). Relationship identifiers are read without firing faults.
/// Not actor-bound: call it on the context's own actor (main or `@ModelActor`).
public enum SessionRecordLoader {
    public static func load(from context: ModelContext, in interval: DateInterval? = nil) throws -> [SessionRecord] {
        var sessionDescriptor = FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startDate)])
        if let interval {
            let start = interval.start, end = interval.end
            sessionDescriptor.predicate = #Predicate { $0.startDate >= start && $0.startDate < end }
        }
        let sessions = try context.fetch(sessionDescriptor)
        guard !sessions.isEmpty else { return [] }

        let instruments = Dictionary(
            try context.fetch(FetchDescriptor<Instrument>()).map { ($0.persistentModelID, $0.id) },
            uniquingKeysWith: { a, _ in a })
        let items = Dictionary(
            try context.fetch(FetchDescriptor<PracticeItem>()).map { ($0.persistentModelID, ($0.id, $0.category)) },
            uniquingKeysWith: { a, _ in a })

        var segmentDescriptor = FetchDescriptor<SessionSegment>()
        if let interval {
            // Segments start at or after their session; pad for sessions crossing the boundary.
            let start = interval.start, end = interval.end.addingTimeInterval(24 * 3600)
            segmentDescriptor.predicate = #Predicate { $0.startDate >= start && $0.startDate < end }
        }
        var segmentsBySession: [PersistentIdentifier: [SegmentRecord]] = [:]
        for segment in try context.fetch(segmentDescriptor) {
            guard let sessionID = segment.session?.persistentModelID else { continue }
            let item = segment.item.flatMap { items[$0.persistentModelID] }
            segmentsBySession[sessionID, default: []].append(
                SegmentRecord(itemID: item?.0, category: item?.1, duration: segment.activeDuration))
        }

        return sessions.map { session in
            SessionRecord(
                id: session.id,
                startDate: session.startDate,
                activeDuration: session.activeDuration,
                instrumentID: session.instrument.flatMap { instruments[$0.persistentModelID] },
                rating: session.rating,
                focus: session.focus,
                tags: session.tags,
                segments: segmentsBySession[session.persistentModelID] ?? [])
        }
    }
}
