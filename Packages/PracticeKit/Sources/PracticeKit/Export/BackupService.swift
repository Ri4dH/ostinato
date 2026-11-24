import Foundation
import SwiftData

public struct ImportSummary: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var skipped = 0
}

public enum BackupError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            String(localized: "This backup was made by a newer version of Ostinato. Update the app and try again.", bundle: .module)
        case .unreadable:
            String(localized: "This file isn't an Ostinato backup.", bundle: .module)
        }
    }
}

@MainActor
public enum BackupService {
    // MARK: Export

    public static func makeBackup(from context: ModelContext, goal: GoalSettings?) throws -> BackupDocument {
        let instruments = try context.fetch(FetchDescriptor<Instrument>())
        let items = try context.fetch(FetchDescriptor<PracticeItem>())
        let sessions = try context.fetch(FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startDate)]))
        let tempos = try context.fetch(FetchDescriptor<TempoEntry>())
        let recordings = try context.fetch(FetchDescriptor<Recording>())

        return BackupDocument(
            version: BackupDocument.currentVersion,
            exportedAt: Date(),
            instruments: instruments.map {
                .init(id: $0.id, name: $0.name, presetKey: $0.presetKey, symbolName: $0.symbolName,
                      colorHex: $0.colorHex, transposition: $0.transposition, sortIndex: $0.sortIndex,
                      isArchived: $0.isArchived, createdAt: $0.createdAt)
            },
            items: items.map {
                .init(id: $0.id, title: $0.title, composer: $0.composer, category: $0.categoryRaw,
                      status: $0.statusRaw, targetTempo: $0.targetTempo, lastTempo: $0.lastTempo,
                      notes: $0.notes, sortIndex: $0.sortIndex, createdAt: $0.createdAt,
                      updatedAt: $0.updatedAt, instrumentID: $0.instrument?.id)
            },
            sessions: sessions.map { s in
                .init(id: s.id, startDate: s.startDate, endDate: s.endDate, activeDuration: s.activeDuration,
                      source: s.sourceRaw, rating: s.rating, focus: s.focus, notes: s.notes, tags: s.tags,
                      instrumentID: s.instrument?.id,
                      segments: s.sortedSegments.map {
                          .init(id: $0.id, startDate: $0.startDate, endDate: $0.endDate,
                                activeDuration: $0.activeDuration, label: $0.label,
                                sortIndex: $0.sortIndex, itemID: $0.item?.id)
                      },
                      pauses: (s.pauses ?? []).map { .init(id: $0.id, startDate: $0.startDate, endDate: $0.endDate) })
            },
            tempoEntries: tempos.map {
                .init(id: $0.id, date: $0.date, bpm: $0.bpm, source: $0.sourceRaw, itemID: $0.item?.id)
            },
            recordings: recordings.map {
                .init(id: $0.id, createdAt: $0.createdAt, duration: $0.duration, audioFileName: $0.audioFileName,
                      fileLocation: $0.fileLocationRaw, offsetInSession: $0.offsetInSession, title: $0.title,
                      sessionID: $0.session?.id, segmentID: $0.segment?.id, itemID: $0.item?.id)
            },
            goal: goal
        )
    }

    public static func encode(_ document: BackupDocument) throws -> Data {
        try BackupDocument.encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        guard let document = try? BackupDocument.decoder.decode(BackupDocument.self, from: data) else {
            throw BackupError.unreadable
        }
        guard document.version <= BackupDocument.currentVersion else {
            throw BackupError.unsupportedVersion(document.version)
        }
        return document
    }

    // MARK: Import (merge by UUID, never duplicate)

    /// Merges a backup into the store. Existing records (same UUID) are kept;
    /// items are updated only when the backup copy is newer.
    @discardableResult
    public static func merge(_ doc: BackupDocument, into context: ModelContext) throws -> ImportSummary {
        var summary = ImportSummary()
        var instruments = try index(context.fetch(FetchDescriptor<Instrument>()), \.id)
        var items = try index(context.fetch(FetchDescriptor<PracticeItem>()), \.id)
        let sessionIDs = Set(try context.fetch(FetchDescriptor<PracticeSession>()).map(\.id))
        var segments = try index(context.fetch(FetchDescriptor<SessionSegment>()), \.id)
        let tempoIDs = Set(try context.fetch(FetchDescriptor<TempoEntry>()).map(\.id))
        let recordingIDs = Set(try context.fetch(FetchDescriptor<Recording>()).map(\.id))
        var sessionsByID: [UUID: PracticeSession] = [:]

        for dto in doc.instruments {
            if instruments[dto.id] != nil { summary.skipped += 1; continue }
            let i = Instrument(id: dto.id, name: clean(dto.name, max: 100), presetKey: dto.presetKey,
                               symbolName: clean(dto.symbolName, max: 100), colorHex: clean(dto.colorHex, max: 9),
                               transposition: max(-36, min(36, dto.transposition)), sortIndex: dto.sortIndex,
                               createdAt: dto.createdAt)
            i.isArchived = dto.isArchived
            context.insert(i)
            instruments[dto.id] = i
            summary.inserted += 1
        }

        for dto in doc.items {
            let instrument = dto.instrumentID.flatMap { instruments[$0] }
            if let existing = items[dto.id] {
                guard dto.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                apply(dto, to: existing, instrument: instrument)
                summary.updated += 1
                continue
            }
            let item = PracticeItem(id: dto.id, title: "", createdAt: dto.createdAt)
            context.insert(item)
            apply(dto, to: item, instrument: instrument)
            items[dto.id] = item
            summary.inserted += 1
        }

        for dto in doc.sessions {
            if sessionIDs.contains(dto.id) { summary.skipped += 1; continue }
            let s = PracticeSession(id: dto.id, startDate: dto.startDate, endDate: dto.endDate,
                                    activeDuration: max(0, dto.activeDuration),
                                    source: SessionSource(rawValue: dto.source) ?? .manual,
                                    instrument: dto.instrumentID.flatMap { instruments[$0] })
            s.rating = dto.rating.map(SessionWriter.clampRating)
            s.focus = dto.focus.map(SessionWriter.clampRating)
            s.notes = clean(dto.notes, max: 20_000)
            s.tags = SessionWriter.normalizedTags(dto.tags.map { clean($0, max: 50) })
            context.insert(s)
            s.segments = dto.segments.compactMap { seg in
                guard segments[seg.id] == nil else { return nil }
                let segment = SessionSegment(id: seg.id, startDate: seg.startDate, endDate: seg.endDate,
                                             activeDuration: max(0, seg.activeDuration),
                                             label: seg.label.map { clean($0, max: 200) },
                                             sortIndex: seg.sortIndex, item: seg.itemID.flatMap { items[$0] })
                context.insert(segment)
                segments[seg.id] = segment
                return segment
            }
            s.pauses = dto.pauses.map {
                let p = PauseInterval(id: $0.id, startDate: $0.startDate, endDate: $0.endDate)
                context.insert(p)
                return p
            }
            sessionsByID[dto.id] = s
            summary.inserted += 1
        }

        for dto in doc.tempoEntries {
            if tempoIDs.contains(dto.id) { summary.skipped += 1; continue }
            let t = TempoEntry(id: dto.id, date: dto.date, bpm: max(1, min(dto.bpm, 400)),
                               source: TempoSource(rawValue: dto.source) ?? .manual)
            context.insert(t)
            t.item = dto.itemID.flatMap { items[$0] }
            summary.inserted += 1
        }

        for dto in doc.recordings {
            // Never trust file names from outside: no paths, no traversal.
            guard !recordingIDs.contains(dto.id), RecordingStorage.isValidFileName(dto.audioFileName) else {
                summary.skipped += 1
                continue
            }
            let r = Recording(id: dto.id, createdAt: dto.createdAt, duration: max(0, dto.duration),
                              audioFileName: dto.audioFileName,
                              fileLocation: FileLocation(rawValue: dto.fileLocation) ?? .local,
                              offsetInSession: dto.offsetInSession, title: clean(dto.title, max: 200))
            context.insert(r)
            r.session = dto.sessionID.flatMap { sessionsByID[$0] }
            r.segment = dto.segmentID.flatMap { segments[$0] }
            r.item = dto.itemID.flatMap { items[$0] }
            summary.inserted += 1
        }

        try context.save()
        return summary
    }

    private static func apply(_ dto: BackupDocument.ItemDTO, to item: PracticeItem, instrument: Instrument?) {
        item.title = clean(dto.title, max: 300)
        item.composer = dto.composer.map { clean($0, max: 200) }
        item.categoryRaw = ItemCategory(rawValue: dto.category)?.rawValue ?? ItemCategory.other.rawValue
        item.statusRaw = ItemStatus(rawValue: dto.status)?.rawValue ?? ItemStatus.learning.rawValue
        item.targetTempo = dto.targetTempo.map { max(1, min($0, 400)) }
        item.lastTempo = dto.lastTempo.map { max(1, min($0, 400)) }
        item.notes = clean(dto.notes, max: 20_000)
        item.sortIndex = dto.sortIndex
        item.instrument = instrument
        item.updatedAt = dto.updatedAt
    }

    private static func clean(_ value: String, max length: Int) -> String {
        String(value.prefix(length))
    }

    private static func index<T>(_ values: [T], _ key: KeyPath<T, UUID>) -> [UUID: T] {
        Dictionary(values.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { first, _ in first })
    }
}
