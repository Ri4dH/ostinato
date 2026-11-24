import Foundation
import SwiftData

/// A repertoire entry: a piece, exercise, scale, or technique.
@Model
public final class PracticeItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var composer: String?
    public var categoryRaw: String = ItemCategory.piece.rawValue
    public var statusRaw: String = ItemStatus.learning.rawValue
    public var targetTempo: Int?
    public var lastTempo: Int?
    public var notes: String = ""
    public var sortIndex: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var instrument: Instrument?

    @Relationship(deleteRule: .nullify, inverse: \SessionSegment.item)
    public var segments: [SessionSegment]? = []

    @Relationship(deleteRule: .nullify, inverse: \Recording.item)
    public var recordings: [Recording]? = []

    @Relationship(deleteRule: .cascade, inverse: \TempoEntry.item)
    public var tempoLog: [TempoEntry]? = []

    public init(
        id: UUID = UUID(),
        title: String,
        composer: String? = nil,
        category: ItemCategory = .piece,
        status: ItemStatus = .learning,
        targetTempo: Int? = nil,
        instrument: Instrument? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.categoryRaw = category.rawValue
        self.statusRaw = status.rawValue
        self.targetTempo = targetTempo
        self.instrument = instrument
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    public var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .learning }
        set { statusRaw = newValue.rawValue; updatedAt = Date() }
    }

    public var isArchived: Bool { status == .archived }

    /// Total practiced time across every segment linked to this item.
    public var totalPracticed: TimeInterval {
        (segments ?? []).reduce(0) { $0 + $1.activeDuration }
    }

    /// Records a tempo and updates `lastTempo`.
    @discardableResult
    public func logTempo(_ bpm: Int, source: TempoSource, date: Date = Date()) -> TempoEntry {
        let entry = TempoEntry(date: date, bpm: bpm, source: source)
        entry.item = self
        lastTempo = bpm
        updatedAt = date
        return entry
    }
}
