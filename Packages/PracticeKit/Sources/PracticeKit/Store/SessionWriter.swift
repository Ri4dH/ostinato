import Foundation
import SwiftData

/// Writes finished and manually logged sessions into SwiftData.
@MainActor
public enum SessionWriter {
    /// Inserts a finished session. Idempotent: a session whose ID already
    /// exists is returned unchanged, so a payload delivered twice (e.g. from
    /// the watch) is stored exactly once.
    @discardableResult
    public static func insert(_ finished: FinishedSession, into context: ModelContext) throws -> PracticeSession {
        if let existing = try fetchSession(id: finished.id, in: context) {
            return existing
        }
        let session = PracticeSession(
            id: finished.id,
            startDate: finished.startDate,
            endDate: finished.endDate,
            activeDuration: finished.activeDuration,
            source: finished.source,
            instrument: try finished.instrumentID.flatMap { try fetchInstrument(id: $0, in: context) }
        )
        session.notes = finished.notes
        session.rating = finished.rating.map(clampRating)
        session.focus = finished.focus.map(clampRating)
        session.tags = normalizedTags(finished.tags)
        context.insert(session)

        var segments: [SessionSegment] = []
        for (index, seg) in finished.segments.enumerated() {
            let item = try seg.target.itemID.flatMap { try fetchItem(id: $0, in: context) }
            let segment = SessionSegment(
                id: seg.id,
                startDate: seg.startDate,
                endDate: seg.endDate,
                activeDuration: max(0, seg.activeDuration),
                label: item == nil ? seg.target.title : nil,
                sortIndex: index,
                item: item
            )
            context.insert(segment)
            segments.append(segment)
            item?.updatedAt = max(item?.updatedAt ?? .distantPast, seg.endDate)
        }
        session.segments = segments

        session.pauses = finished.pauses.map { interval in
            let pause = PauseInterval(startDate: interval.start, endDate: interval.end)
            context.insert(pause)
            return pause
        }
        session.recomputeDuration()
        try linkRecordings(to: session, segments: segments, sessionID: finished.id, in: context)
        try context.save()
        return session
    }

    private static func linkRecordings(
        to session: PracticeSession, segments: [SessionSegment], sessionID: UUID, in context: ModelContext
    ) throws {
        let pending = try context.fetch(FetchDescriptor<Recording>(predicate: #Predicate { $0.sessionRefID == sessionID }))
        for recording in pending {
            recording.session = session
            if let segmentID = recording.segmentRefID {
                recording.segment = segments.first { $0.id == segmentID }
                if recording.item == nil { recording.item = recording.segment?.item }
            }
        }
    }

    public static func fetchSession(id: UUID, in context: ModelContext) throws -> PracticeSession? {
        var descriptor = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public static func fetchItem(id: UUID, in context: ModelContext) throws -> PracticeItem? {
        var descriptor = FetchDescriptor<PracticeItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public static func fetchInstrument(id: UUID, in context: ModelContext) throws -> Instrument? {
        var descriptor = FetchDescriptor<Instrument>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Trims, drops empties and de-duplicates (case-insensitive), keeping order.
    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func clampRating(_ value: Int) -> Int { min(5, max(1, value)) }
}
